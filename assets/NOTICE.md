# Data notice

`cities.json` is derived from the GeoNames `cities15000`, `admin1CodesASCII`
and `countryInfo` dumps (https://www.geonames.org/), licensed under Creative
Commons Attribution 4.0 (https://creativecommons.org/licenses/by/4.0/).
Trimmed to name, region, country, latitude, longitude and timezone by `dev/build-cities`.

`land.json` is a 2° land mask rasterised by `dev/build-land` from Natural Earth's
1:110m admin-0 countries (https://www.naturalearthdata.com/), which is in the
public domain.

## Adhan recordings (`adhans/`)

### From the Prayer Times & Quran browser extension — no licence

`makkah.ogg`, `madinah.ogg`, `al-aqsa.ogg`, `mishary.ogg`, `fajr-ali-mulla.ogg`,
`fajr-madinah.ogg`, `fajr-mishary.ogg` were taken from the Prayer Times & Quran Chrome extension
(id `fbkmgnkliklgbmanjkmiihkdioepnkce`, v3.0.11, files 5, 14, 6, 7, 13, 15, 11) and transcoded
to Opus in their original channel layout by `dev/build-adhans` (never downmixed: Mishary's adhan is nearly phase-inverted between channels, and a mono mix left mostly reverb). The extension states no licence for them; recordings of the Haramain
adhans are generally Saudi broadcast recordings, and no licence permitting redistribution was
found. **The maintainer chose on 2026-10-06 to accept that copyright risk** and include them, as other
prayer extensions do. The Fajr recordings were checked by transcription to contain "الصلاة خير
من النوم".

### Freely licensed, from Wikimedia Commons

Each of these was transcoded to Opus (64 kbit/s) from the Wikimedia Commons original. Their content was
checked by transcribing them (Whisper, Arabic) before inclusion. None of these three contains the Fajr phrase
"الصلاة خير من النوم".

| File | Original | Author | Licence |
|---|---|---|---|
| `aaqib-azeez.ogg` | https://commons.wikimedia.org/wiki/File:The_Adhan_-_Muslim_Call_to_Prayer_-_Aaqib_Azeez.mp3 | Atcovi (titled as recited by Aaqib Azeez) | CC BY-SA 4.0, https://creativecommons.org/licenses/by-sa/4.0/ — this transcoded copy is under the same licence |
| `sabah-fakhri.ogg` | https://commons.wikimedia.org/wiki/File:Call_to_prayer_by_Sabah_Fakhry.mp3 | Sabah Fakhri | Public domain (as marked on Commons) |
| `beautiful-adhan.ogg` | https://commons.wikimedia.org/wiki/File:Beautiful_adhan.ogg | Adam-synagda | CC0 1.0, http://creativecommons.org/publicdomain/zero/1.0/ |

## Lunar theory

The moon's periodic terms in `Model.js` (`MOON_LR`, `MOON_B`; Meeus, *Astronomical Algorithms*,
ch. 47) are taken from the astronomia library, https://github.com/commenthol/astronomia,
MIT licence, © 2013 Sonia Keys, © 2016 commenthol.

## The sky (`sky.json`)

Stars, star names (including the Arabic names), constellation lines and the planets' orbital
elements are derived by `dev/build-sky` from d3-celestial's data,
https://github.com/ofrohn/d3-celestial:

> Copyright (c) 2015, Olaf Frohn. All rights reserved. Redistribution and use in source and
> binary forms, with or without modification, are permitted provided that the following
> conditions are met: 1. Redistributions of source code must retain the above copyright notice,
> this list of conditions and the following disclaimer. 2. Redistributions in binary form must
> reproduce the above copyright notice, this list of conditions and the following disclaimer in
> the documentation and/or other materials provided with the distribution. 3. Neither the name of
> the copyright holder nor the names of its contributors may be used to endorse or promote
> products derived from this software without specific prior written permission. THIS SOFTWARE
> IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
> WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
> FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
> CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
> CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
> SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
> THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
> OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
> POSSIBILITY OF SUCH DAMAGE.

The planetary elements in that data are JPL's "Keplerian Elements for Approximate Positions of
the Major Planets" (E. M. Standish), a US government work.

## Quran verses (`verses.json`)

The Arabic text is the Tanzil Quran Text (quran-simple), Copyright (C) 2007-2024 Tanzil Project,
https://tanzil.net, used verbatim (only the opening basmala of a surah's first verse and the ۞
section mark are not shown, as neither is part of the verse); the Tanzil terms permit verbatim
copying with attribution and a link, and forbid changing the text. The English is Mohammed
Marmaduke Pickthall's translation (1930), in the public domain. Both were fetched by reference from
api.alquran.cloud by `dev/build-verses`; none was typed by hand.
