#!/usr/bin/env node
// Validate the checked-in WebAssembly ABI and its memory ownership from Node.
// No Rust or npm dependencies are required to consume/check the artifact.

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const wasmPath = fileURLToPath(
  new URL('../prebuilt/web/mdx_native.wasm', import.meta.url),
);
const wasmBytes = await readFile(wasmPath);
const module = new WebAssembly.Module(wasmBytes);

assert.deepEqual(
  WebAssembly.Module.imports(module),
  [],
  'the parser wasm must not require JavaScript imports',
);

const exported = WebAssembly.Module.exports(module);
const requiredFunctions = [
  'mdx_alloc',
  'mdx_dealloc',
  'mdx_parse',
  'mdx_free',
  'mdx_abi_version',
  'mdx_ir_version',
  'mdx_build_info',
];
for (const name of requiredFunctions) {
  assert(
    exported.some((entry) => entry.name === name && entry.kind === 'function'),
    `missing wasm function export: ${name}`,
  );
}
assert(
  exported.some((entry) => entry.name === 'memory' && entry.kind === 'memory'),
  'missing exported wasm memory',
);

const instance = new WebAssembly.Instance(module);
const {
  memory,
  mdx_alloc: allocate,
  mdx_dealloc: deallocate,
  mdx_parse: parse,
  mdx_free: freeResult,
  mdx_abi_version: abiVersion,
  mdx_ir_version: irVersion,
} = instance.exports;
assert.equal(abiVersion(), 2, 'unexpected ABI version');
assert.equal(irVersion(), 6, 'unexpected IR version');
assert(
  !exported.some((entry) => entry.name === 'mdx_wasm_abi_version'),
  'the old mdx_wasm_abi_version export must be gone',
);

const u32 = (value) => value >>> 0;

function parseAndCopy(markdown) {
  const sourceBytes = new TextEncoder().encode(markdown);
  let sourcePtr = null;
  let lengthPtr = null;
  let resultPtr = null;
  let resultLength = 0;

  try {
    sourcePtr = u32(allocate(sourceBytes.length));
    lengthPtr = u32(allocate(4));

    // Allocations can grow memory and detach older views. Always construct a
    // fresh view from the current exported memory buffer after allocating.
    if (sourceBytes.length > 0) {
      new Uint8Array(memory.buffer, sourcePtr, sourceBytes.length).set(sourceBytes);
    }
    new DataView(memory.buffer).setUint32(lengthPtr, 0xffff_ffff, true);

    resultPtr = u32(parse(sourcePtr, sourceBytes.length, lengthPtr));
    resultLength = new DataView(memory.buffer).getUint32(lengthPtr, true);
    assert(
      resultPtr + resultLength <= memory.buffer.byteLength,
      'parser result points outside wasm memory',
    );

    // Copy before calling freeResult. Callers must not keep a view into the
    // Rust-owned allocation after it has been released.
    return new Uint8Array(memory.buffer, resultPtr, resultLength).slice();
  } finally {
    if (resultPtr !== null) freeResult(resultPtr, resultLength);
    if (lengthPtr !== null) deallocate(lengthPtr, 4);
    if (sourcePtr !== null) deallocate(sourcePtr, sourceBytes.length);
  }
}

// The IR starts with the magic "MDXI" and the little-endian IR version.
const irHeader = [0x4d, 0x44, 0x58, 0x49, irVersion(), 0, 0, 0];
// Empty input exercises a zero-length source allocation. The IR is the header
// followed by an empty block list (one little-endian zero count), and mdx_parse
// must overwrite the four-byte length.
assert.deepEqual(parseAndCopy(''), Uint8Array.of(...irHeader, 0, 0, 0, 0));
// The wasm deallocators are specified as null-safe no-ops.
deallocate(0, 0);
deallocate(0, 4);
freeResult(0, 0);
freeResult(0, 4);


// Failure contract: a null source with a non-zero length returns null and
// writes 0 to out_len.
{
  const lengthPtr = u32(allocate(4));
  new DataView(memory.buffer).setUint32(lengthPtr, 0xffff_ffff, true);
  assert.equal(parse(0, 5, lengthPtr), 0, 'null source must return null');
  assert.equal(new DataView(memory.buffer).getUint32(lengthPtr, true), 0);
  deallocate(lengthPtr, 4);
}

// mdx_build_info is a static NUL-terminated string identifying the build.
{
  const infoPtr = u32(instance.exports.mdx_build_info());
  const bytes = new Uint8Array(memory.buffer, infoPtr);
  const info = new TextDecoder().decode(bytes.subarray(0, bytes.indexOf(0)));
  assert.match(info, /^mdx_native \d+\.\d+\.\d+ abi=2 ir=6$/);
}

const unicodeFixture = '# 日本語の見出し 🐱\n\nCafé, naïve, Ελληνικά, 漢字.\n';
const unicodeExpected = parseAndCopy(unicodeFixture);
assert(unicodeExpected.byteLength > irHeader.length + 4);
assert.deepEqual(Array.from(unicodeExpected.slice(0, 8)), irHeader);
for (let iteration = 0; iteration < 8; iteration++) {
  assert.deepEqual(parseAndCopy(unicodeFixture), unicodeExpected);
}

// This single large paragraph exceeds the module's initial linear memory.
// Keep the pre-parse buffer to verify memory.grow detaches old JS views, then
// confirm parsing remains deterministic over repeated allocate/parse/free
// cycles.
const largeFixture = '長文 😀 café αβγ —'.repeat(80_000);
const oldMemoryBuffer = memory.buffer;
const largeExpected = parseAndCopy(largeFixture);
assert(largeExpected.byteLength > 0);
assert.notStrictEqual(memory.buffer, oldMemoryBuffer, 'large input should grow wasm memory');
assert.equal(oldMemoryBuffer.byteLength, 0, 'memory growth should detach old JS views');
for (let iteration = 0; iteration < 3; iteration++) {
  assert.deepEqual(parseAndCopy(largeFixture), largeExpected);
}

console.log(
  `WASM ABI v${abiVersion()} / IR v${irVersion()} ok: no imports, Unicode round trips, large repeated parse/free, zero-length and null-safe frees.`,
);
