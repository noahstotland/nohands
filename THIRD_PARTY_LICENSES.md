# Third-party licenses

NoHands ships no model and no third-party binary in this repo. Models are downloaded at run time, by FluidAudio or by the user through Ollama. FluidAudio is the only compiled-in dependency: it comes in through SwiftPM, pinned to 0.18.2 (commit `e396cf780c4abf8e395087467c0585d3b0d17f68`), from <https://github.com/FluidInference/FluidAudio>, under Apache-2.0.

NoHands uses only `VadManager` and `AsrManager` / `AsrModels` from FluidAudio. It uses no diarizer and no text-to-speech.

NoHands itself is under Apache-2.0, see [LICENSE](LICENSE). Anyone who hands out a built `NoHands.app` must include `LICENSE` and this file with it. `scripts/bundle.sh` does not copy them into the app today.

All licence facts below were checked against the upstream pages on 2026-11-08.

## Components

| Component | How it reaches the user | Licence | Source | Compatible with Apache-2.0? | Attribution needed |
|---|---|---|---|---|---|
| FluidAudio 0.18.2 | Compiled into the app | Apache-2.0. No `NOTICE` file in its repo root | <https://github.com/FluidInference/FluidAudio> | Yes | Keep its `LICENSE` copy (below) and the notices in [FluidAudio's own third-party notices](#fluidaudios-own-third-party-notices) |
| Silero VAD, via `FluidInference/silero-vad-coreml` | Downloaded at run time | MIT, Copyright (c) 2020-present Silero Team (see note 1) | <https://huggingface.co/FluidInference/silero-vad-coreml>, <https://github.com/snakers4/silero-vad/blob/master/LICENSE> | Yes | Keep the MIT notice with any copy of the model |
| Parakeet TDT 0.6b v2, via `FluidInference/parakeet-tdt-0.6b-v2-coreml`. The default (`asrModelVersion: "v2"`) | Downloaded at run time | CC-BY-4.0 (<https://creativecommons.org/licenses/by/4.0/>). Commercial use is allowed, per the NVIDIA page | <https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml>, original <https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2> | Yes, as a separately downloaded model | Credit NVIDIA as the author, name the model, link the licence, and say the Core ML conversion is by FluidInference and was changed from the original |
| Parakeet TDT 0.6b v3, via `FluidInference/parakeet-tdt-0.6b-v3-coreml` (`asrModelVersion: "v3"`) | Downloaded at run time | CC-BY-4.0 (see note 2) | <https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml>, original <https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3> | Yes, as a separately downloaded model | Same as v2 |
| `qwen2.5:7b-instruct` (Ollama) | Pulled by the user with `scripts/setup-local-model.sh`. The default on Macs with 12 GB of RAM or more | Apache-2.0 | <https://ollama.com/library/qwen2.5:7b-instruct>, <https://huggingface.co/Qwen/Qwen2.5-7B-Instruct> | Yes | None for NoHands, which does not redistribute the model |
| `qwen2.5:3b-instruct` (Ollama) | Pulled by the user. The default on Macs with under 12 GB of RAM (`Sources/NoHandsCore/AppConfig.swift`, `defaultLocalModel`, which reads `physicalMemory`) | Qwen Research License Agreement, release date September 19, 2024. **Research and evaluation only** (see note 3) | <https://ollama.com/library/qwen2.5:3b-instruct>, <https://huggingface.co/Qwen/Qwen2.5-3B-Instruct/blob/main/LICENSE> | Not applicable: NoHands ships and redistributes nothing of it. **Flagged**: it limits commercial use | See note 3 |

### Notes and flags

1. **Silero VAD.** The upstream README badge has the alt text "CC BY-NC", but the `LICENSE` file and the badge URL both say MIT. The `LICENSE` file governs, so NoHands treats it as MIT.
2. **Parakeet v3.** The FluidInference v3 Core ML page has the tag `cc-by-4.0`, but its body says "Apache 2.0. See the FluidAudio repository". NVIDIA's page and the tag say CC-BY-4.0, so NoHands treats it as CC-BY-4.0. This is a conflict on the FluidInference page, not in NoHands.
3. **Qwen 2.5 3B is research-only. Flagged.**
   - Section 1(i): "Non-Commercial" shall mean for research or evaluation purposes only.
   - Section 2(a): the licence is granted "FOR NON-COMMERCIAL PURPOSES ONLY".
   - Section 2(b): "If you are commercially using the Materials, you shall request a license from us."
   - Redistribution (Section 3) requires giving recipients a copy of the agreement, noting modifications, and keeping this notice in a Notice text file: "Qwen is licensed under the Qwen RESEARCH LICENSE AGREEMENT, Copyright (c) Alibaba Cloud. All Rights Reserved."
   - Section 4(b) requires "Built with Qwen" or "Improved using Qwen" only when the Materials or their outputs are used to create, train, fine-tune or improve a distributed AI model. NoHands does not do that.

   NoHands does not conflict with this licence, because it does not ship or redistribute the model: the user downloads it from Ollama. But a person who uses NoHands commercially on a Mac with under 12 GB of RAM, on the 3B model, is outside its terms. That person should set `localModel` to `qwen2.5:7b-instruct` in `~/.config/nohands/config.json` (see Configuration in [README.md](README.md)), use Claude, or get a licence from Alibaba Cloud. The 3B model stays the low-memory default for now. Changing it needs its own ticket.

## FluidAudio licence

Verbatim copy of `LICENSE` from FluidAudio at commit `e396cf780c4abf8e395087467c0585d3b0d17f68`. The appendix is FluidAudio's unfilled boilerplate, so no copyright holder is named in it.

```text
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
```

## FluidAudio's own third-party notices

FluidAudio's repo has a `ThirdPartyLicenses/` folder. For each file there, and for the target list in FluidAudio's `Package.swift`, this section records whether the code or data is part of a built NoHands app and, if it is, the notice that goes with it.

NoHands builds with the Swift 6.0 toolchain, which reads FluidAudio's `Package.swift` (not `Package@swift-6.2.swift`, the one with opt-out traits). That manifest compiles and links every FluidAudio target, including the text-to-speech and diarizer code that NoHands never calls. This was checked against a release build of NoHands from 2026-11-04: the binary contains symbols from the Rust text-processing library, from fastcluster and from the LuxTTS code, and the finished `NoHands.app` holds a copy of `FluidAudio_LuxTtsG2pResources.bundle`, because `scripts/bundle.sh` copies every `*.bundle` into the app.

Other ports are credited only in FluidAudio source comments (for example the NeMo Sortformer state updater and LocalVQE). They are not listed in `ThirdPartyLicenses/` and were not audited here.

### Applies: NemoTextProcessing (text-processing-rs)

- Name: `NemoTextProcessing` binary target, a prebuilt xcframework of `text-processing-rs`. `Package.swift` pins release v0.3.1. FluidAudio's notice file says v0.3.0.
- Licence: Apache-2.0 (full text above).
- Source: <https://github.com/FluidInference/text-processing-rs>
- Linked into the NoHands binary through the `FluidAudio` library target.

It statically links these works, all permissive:

| Work | Licence | Source | Copyright |
|---|---|---|---|
| NVIDIA NeMo Text Processing. The compiled grammars and fixtures come from it (pinned commit `1f1263579fe57ba7ed783cad3dddee710fcc5064`) | Apache-2.0 | <https://github.com/NVIDIA/NeMo-text-processing> | Copyright (c) NVIDIA CORPORATION & AFFILIATES. |
| rustfst | MIT OR Apache-2.0 | <https://github.com/Garvys/rustfst> | Copyright (c) Alexandre Caulier and the rustfst contributors. |
| flate2 | MIT OR Apache-2.0 | <https://github.com/rust-lang/flate2-rs> | Copyright (c) Alex Crichton and the flate2 contributors. |

It also links other permissive Rust crates (MIT and/or Apache-2.0) through `rustfst` and `flate2`: `nom`, `miniz_oxide`, `bitflags`, `anyhow` and `lazy_static`. **Open item:** neither FluidAudio nor the upstream `THIRD-PARTY-LICENSES.md` (v0.3.1) gives a copyright line for these crates, so none is reproduced here. Their MIT notices are on crates.io and in the upstream `Cargo.lock`. This needs an owner decision before a binary is handed out.

### Applies: fastcluster

- Name: `FastClusterWrapper` target, which wraps fastcluster's centroid linkage.
- Licence: BSD 2-Clause (the text below).
- Source: <https://github.com/fastcluster/fastcluster>
- Copyright holders: Daniel Müllner (2011, until package version 1.1.23); Google Inc. (all changes from version 1.1.24 on).
- Compiled into the NoHands binary (confirmed by symbol).

Notice, verbatim from FluidAudio's `ThirdPartyLicenses/fastcluster-LICENSE.md`:

```text
Copyright:
  * Until package version 1.1.23: © 2011 Daniel Müllner <https://danifold.net>
  * All changes from version 1.1.24 on: © Google Inc. <https://www.google.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### Applies: VBx clustering

- Name: `VBxClustering.swift`, FluidAudio's Swift implementation of the VBx algorithm from BUT Speech@FIT (<https://github.com/BUTSpeechFIT/VBx>).
- Licence: Apache-2.0. FluidAudio's `vbx-LICENSE.md` is the standard text (same as the licence above) with the appendix filled in.
- Copyright: Copyright 2021-2024 BUT Speech@FIT (original VBx project)
- Compiled into the NoHands binary as part of the diarizer code.

Notice: this Apache-2.0 text, the copyright line above, and the standard boilerplate (Licensed under the Apache License, Version 2.0, <http://www.apache.org/licenses/LICENSE-2.0>), which the licence text above already carries.

### Applies: Japanese text frontend (Kokoro ANE)

- Name: Swift ports in `Sources/FluidAudio/TTS/KokoroAne/G2P/Japanese/` (`JapaneseCutlet.swift` and related files). They are ports of Misaki's `cutlet.py` and `num2kana.py`.
- Compiled into the NoHands binary (the type names are present in it). The data they read (the word list and the MeCab dictionary) is downloaded only by Kokoro text-to-speech, which NoHands never calls, so it is not part of NoHands (see the list further down).

| Work | Licence | Source | Copyright |
|---|---|---|---|
| hexgrad/misaki (`cutlet.py`) | Apache-2.0 (text above) | <https://github.com/hexgrad/misaki> | FluidAudio's file names no copyright holder (its appendix is unfilled). Credit: hexgrad/misaki |
| polm/cutlet, which Misaki adapted | MIT | <https://github.com/polm/cutlet> | Copyright (c) 2020 Paul O'Leary McCann |
| Greatdane/Convert-Numbers-to-Japanese, copied into Misaki's `num2kana.py` | MIT | <https://github.com/Greatdane/Convert-Numbers-to-Japanese> | Copyright (c) 2018 David Wilson |

polm/cutlet, verbatim from FluidAudio's `ThirdPartyLicenses/JapaneseG2P-LICENSE.md`:

```text
MIT License

Copyright (c) 2020 Paul O'Leary McCann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Greatdane/Convert-Numbers-to-Japanese, same source:

```text
The MIT License (MIT)
Copyright (c) 2018 David Wilson, https://github.com/Greatdane

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

### Applies, and open: LuxTTS English G2P data

**Flagged for the owner. This is a possible licence conflict in a built app.**

- Name: `Sources/LuxTtsG2pResources/Resources/luxtts_en_us_lexicon.tsv.zz` and `luxtts_en_us_g2p_aux.json`, shipped as `FluidAudio_LuxTtsG2pResources.bundle`.
- FluidAudio's own file says these two data files "are **not** covered by FluidAudio's Apache-2.0 license alone" and that "Apps that don't use LuxTTS can leave both files out of their bundle."
- They reach NoHands: the bundle is built into every NoHands build, and `scripts/bundle.sh` copies it into `NoHands.app/Contents/Resources/`. NoHands never calls LuxTTS, so the data is never read.

What the files are made of, from FluidAudio's `ThirdPartyLicenses/LuxTtsEnglishG2P-LICENSE.md`:

| Content | Source | Licence |
|---|---|---|
| Pronunciations in the lexicon (139k words by context variants) | Output of espeak-ng (`en-us`, via piper_phonemize), <https://github.com/espeak-ng/espeak-ng>. Copyright (C) 2005-2014 Jonathan Duddington, Copyright (C) 2015-2026 Reece H. Dunn and contributors | GPL-3.0-or-later |
| Aux tables (multi-word phrases, flag word sets, homograph and capital word lists) | Parsed from espeak-ng `dictsource/en_list` (<https://github.com/rhasspy/espeak-ng>) | GPL-3.0-or-later |
| Lexicon word keys | FrequencyWords 2018 `en_full.txt` (<https://github.com/hermitdave/FrequencyWords>, from OpenSubtitles2018) | CC-BY-SA-4.0 (content) |
| Lexicon word keys | dwyl/english-words `words_alpha.txt` (<https://github.com/dwyl/english-words>) | Unlicense |

The full GPL-3.0 text is in that FluidAudio file and is not copied here, because the way out is to not ship the data. Options for the owner:

1. Stop copying `FluidAudio_LuxTtsG2pResources.bundle` into the app in `scripts/bundle.sh`. The app does not use it. This is a source change, so it needs its own ticket (NH-31 does not touch `scripts/bundle.sh`). Until it is done, do not hand out a built `NoHands.app`.
2. Keep shipping it and meet the GPL-3.0 and CC-BY-SA-4.0 terms for those two files (licence texts, source offer, share-alike). Not recommended.

### Does not apply to NoHands

- **Spanish and French text frontends (ipa-dict MIT, CharsiuG2P MIT).** The lexicon files are hosted on `FluidInference/kokoro-82m-coreml` and downloaded only by Kokoro text-to-speech. Not in this repo, not in the app, never downloaded by NoHands.
- **UniDic / unidic-lite (BSD) and Misaki's `ja_words.txt` (Apache-2.0).** The dictionary and word list are downloaded at run time only by Kokoro's Japanese frontend, which NoHands never calls. Not in the app.
- **`KokoroANE-v3/` (NOTICE, `mattmireles-LICENSE`, `conversion-LICENSE`).** These cover FluidInference's optional model generator and the adapted model files it makes (from mattmireles/kokoro-coreml, Apache-2.0, and laishere/kokoro-coreml, Apache-2.0). NoHands never downloads those models. The compiled Swift file `KokoroAneV3NativeSource.swift` says it is "Inspired by" mattmireles/kokoro-coreml, not copied from it. This is a judgement call: if the owner prefers to be safe, add the NOTICE text from FluidAudio's `ThirdPartyLicenses/KokoroANE-v3/NOTICE` here.
- **`MachTaskSelfWrapper`** has no entry in `ThirdPartyLicenses/` and is part of FluidAudio under its own Apache-2.0 licence.
