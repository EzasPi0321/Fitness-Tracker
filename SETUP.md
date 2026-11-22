# Setting up FitTrack

Every new version is published on the [Releases page](https://github.com/EzasPi0321/Fitness-Tracker/releases/latest). Pick your phone below.

- [Android](#android)
- [iPhone (SideStore)](#iphone-sidestore)
- [Meal photos: add an AI key](#meal-photos-add-an-ai-key)
- [If something goes wrong](#if-something-goes-wrong)

---

## Android

1. On the phone, open the [latest release](https://github.com/EzasPi0321/Fitness-Tracker/releases/latest) and tap **FitTrack.apk** under **Assets**.
2. Open the download. If Android asks, allow your browser to **install unknown apps**, then tap **Install**.
3. Open FitTrack and follow the setup.

**Updates:** when a new version is out, FitTrack shows **New version available** on Today. Tap **Update**, and it installs over the old one, keeping your data.

**Samsung Health / Health Connect (optional):**

1. In FitTrack's setup (or **Settings › Health**), tap **Connect** and allow the permissions.
2. In **Samsung Health › Settings › Health Connect**, turn on sharing for steps, sleep, exercise, weight, water and nutrition.
3. If FitTrack says something is **Not allowed**, open **Settings › Apps › Health Connect › App permissions › FitTrack** and turn those on.

Samsung Health copies new steps across every so often, so give it a few minutes.

---

## iPhone (SideStore)

Apple doesn't allow installing apps from a file, so FitTrack is installed with **SideStore**, which signs it with your own Apple ID.

- **Free Apple ID:** apps last **7 days** at a time. SideStore renews them from the phone, and a Shortcuts automation can do it for you (step 4).
- **Computer:** needed once, for setup. Day to day, SideStore works from the phone alone.
- **Limit:** a free Apple ID can have **3** sideloaded apps, and SideStore counts as one.

### 1. On the computer (once)

1. Install **iloader**, SideStore's setup app, from the guide at [docs.sidestore.io](https://docs.sidestore.io). On Windows, install **iTunes** and **iCloud** from apple.com, not the Microsoft Store.
2. Plug the iPhone in with a cable, unlock it, and tap **Trust This Computer**.
3. In iloader, sign in with your Apple ID and choose **Install SideStore**. This also puts the **pairing file** on the phone, which is what lets it renew apps without the computer.
   - If sign-in fails, change iloader's **Anisette Server** in Settings to another one and try again.

Keep iloader installed. You only need it again if SideStore itself expires, or after a big iOS update breaks the pairing file.

### 2. On the iPhone (once)

1. **Settings › General › VPN & Device Management** › under **Developer App**, tap your Apple ID › **Trust**.
2. **Settings › Privacy & Security › Developer Mode** › turn on and let the phone restart.
3. Install **LocalDevVPN** from the App Store and allow it to add a VPN. SideStore uses it to install and renew apps on the phone. It doesn't send your traffic anywhere.
4. Open **SideStore** and sign in with your Apple ID. If sign-in fails, see [SideStore won't sign in](#sidestore-wont-sign-in).

### 3. Install FitTrack

1. In SideStore, go to **Sources › +** and add:
   ```
   https://github.com/EzasPi0321/Fitness-Tracker/releases/latest/download/source.json
   ```
2. Turn **LocalDevVPN** on.
3. Open the FitTrack source and tap **Get**. It shows **7 DAYS** in **My Apps** when done.
4. Open FitTrack and follow the setup.

**Apple Health isn't available on iPhone this way.** Apple doesn't let apps signed with a free Apple ID use Health, so FitTrack doesn't connect to it directly. Log sleep and weight in the app. Steps can still come in from Apple Health with a shortcut (step 5). Full Health sync would need a paid Apple Developer account and TestFlight.

**Updates:** new versions appear in SideStore from the source. Installing one also renews the 7 days.

### 4. Renew automatically

In **Shortcuts › Automation › + › Charger › Is Connected › Run Immediately**, add:

1. **LocalDevVPN › Connect**, if offered. Otherwise leave the VPN on.
2. **SideStore › Refresh All Apps**

Every time you charge, FitTrack and SideStore get a fresh 7 days.

If an app expires anyway, it just won't open. **Your data is kept.** Refresh in SideStore and it opens again. Don't delete the app to fix it, because that erases its data.

### 5. Steps from Apple Health (optional)

The Shortcuts app can read Apple Health, so a shortcut reads today's steps and sends them to FitTrack each time you open it. The Health app doesn't open; at most a short banner shows.

1. In **Shortcuts**, tap **+** on the Shortcuts tab and name it **FitTrack steps**.
2. Add **Find Health Samples**. Set **Type** to **Steps** and add the filter **Start Date is Today**.
3. Add **Calculate Statistics**, set to **Sum** of **Health Samples**.
4. Add **URL** and type `fittrack://steps?count=`, then insert the **Statistics Result** variable straight after it.
5. Add **Open URLs**. Tap **Done**.
6. On the **Automation** tab, tap **+ › App › FitTrack › Is Opened › Run Immediately**, and choose **FitTrack steps**. Turn off **Notify When Run** to skip the banner.
7. The first run asks to read your steps and to open FitTrack. Tap **Allow**.

You can also tap the pencil on the **Steps** card to type steps in. An earlier run of the shortcut never lowers today's count.

If FitTrack keeps reopening itself after the shortcut runs, change the automation's trigger to **Time of Day** (for example every hour, or 9 pm) instead of **Is Opened**.

---

## Meal photos: add an AI key

Meal photos, AI label reading and body fat estimates use your own Anthropic API key. Barcodes and typing in food work without one.

1. At [console.anthropic.com](https://console.anthropic.com), go to **API keys › Create key**. Leave scope as **Default workspace**.
2. Under **Limits**, set a monthly spend limit so a leaked key can't cost much.
3. Copy the key (it's only shown once) and paste it into FitTrack's **Settings › AI**. It's stored in the phone's secure storage and only sent to Anthropic.
4. Optional: type your credit balance from **Billing** into **Credit balance** below the key, and FitTrack shows roughly how many photos you have left.

**Cost:** on the default **Smart** model, about 1 US cent a photo (Haiku first, Opus only when unsure). Easy photos like a bottle of water cost less than US$0.01.

**Keep the key private:** never post it in a chat, a repository or a message. Friends should make their own key.

---

## If something goes wrong

### SideStore won't sign in

- **"ADI native error":** in SideStore, **Settings › User Customizations › On-Device Anisette** › turn it **off**.
- **"503 Service Temporarily Unavailable" from Apple:** a change on Apple's side broke sign-in on SideStore **0.6.4 and earlier**. Install a newer one: download `SideStore.ipa` from SideStore's [latest release](https://github.com/SideStore/SideStore/releases/latest) (0.7.0-alpha or later), then in iloader use **Import IPA**, and **Manage Pairing File › Place** for SideStore.
- **Which anisette server:** use the one iloader signs in with (for example **jkcoxson**, `mac-ani.jkcoxson.com`), or **#1 SideStore**. Avoid servers that are a bare IP address with `http://`.
- **Still 503 on a new version:** Apple has probably paused sign-ins for your Apple ID after repeated tries. Stop for 12–24 hours, then try once.
- **FitTrack meanwhile:** iloader can install FitTrack directly: download `FitTrack.ipa` from the latest FitTrack release and use **Import IPA**. Re-import it within 7 days to renew it.
- **Experimental builds:** if SideStore says its build is experimental, switch its update channel to **Stable**.
- **Leave alone:** SideJITServer and the Client Configuration screens. FitTrack doesn't need them.

### The computer can't see the iPhone ("no connected devices")

- **Trust the computer:** unlock the phone and tap **Trust This Computer**.
- **Use a data cable:** some cables only charge.
- **Windows:** iTunes and iCloud must be the apple.com versions, not the Microsoft Store ones. The phone should show in iTunes.
- **Mac:** the phone should show in Finder's sidebar.

### Health data missing

- **Android:** see the Samsung Health steps above. FitTrack lists anything not allowed under **Settings › Health**.
- **iPhone:** Apple Health isn't available with a free Apple ID (SideStore or iloader), so FitTrack hides it. Everything else works.
