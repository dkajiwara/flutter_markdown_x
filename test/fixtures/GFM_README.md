# GFM 0.29 extension corpus

`gfm_0.29.json` contains the extension examples of the GitHub Flavored
Markdown Spec, version 0.29 (2019-04-06). They were extracted from
[`test/spec.txt` in github/cmark-gfm](https://github.com/github/cmark-gfm/blob/master/test/spec.txt),
the same spec published at https://github.github.com/gfm/.

Included sections (24 examples): Tables (extension), Task list items
(extension), Strikethrough (extension), Autolinks (extension), and Disallowed
Raw HTML (extension). The two task list examples are marked `disabled` in
spec.txt (cmark-gfm tests them separately); they are kept because their
expected HTML is still the specified output. The `example` field is the
example's ordinal across the whole spec.txt, and `tag` is the marker used in
spec.txt (`table`, `strikethrough`, `autolink`, `tagfilter`, `disabled`).

Copyright (c) GitHub, Inc. and John MacFarlane. The specification is licensed
under the Creative Commons Attribution-ShareAlike 4.0 International License
(CC BY-SA 4.0), as stated in the spec.txt header:
https://creativecommons.org/licenses/by-sa/4.0/.
The fixture is redistributed with attribution and under the same license.
