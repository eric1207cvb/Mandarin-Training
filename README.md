# Mandarin Training

`StudentDict` is a SwiftUI iOS dictionary app using the Ministry of Education's
《重編國語辭典修訂本》data for offline lookup.

## Local setup

1. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig`.
2. Put the local RevenueCat public SDK key in `REVENUECAT_API_KEY`.
3. Open `StudentDict.xcodeproj` in Xcode and resolve Swift Package dependencies.

`Config/Secrets.xcconfig` is intentionally ignored by Git. Never commit API keys,
private tokens, provisioning profiles, or other credentials.

The dictionary data is released by Taiwan's Ministry of Education under the
Creative Commons Attribution-NoDerivs 3.0 Taiwan license. See the app's privacy
policy and the official source page for attribution and use conditions:

<https://language.moe.gov.tw/001/Upload/Files/site_content/M0001/respub/dict_reviseddict_download.html>
