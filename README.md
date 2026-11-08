# Apex Arena Mobile (Godot 4.3, GDScript, بدون صدا)

## ساختار فایل‌ها
- `project.godot`, `export_presets.cfg`
- `Scenes/Main.tscn`  (فقط ریشه؛ همه چیز با کد ساخته می‌شود)
- `Systems/game.gd`   منوی بازی، تایمر ۴ دقیقه، امتیاز، respawn، تنظیمات
- `Player/player.gd`  حرکت: sprint, slide, slide-jump, bunny hop, strafe، تیلت اسلحه
- `Weapons/weapon.gd`, `Weapons/weapon_data.gd`  تفنگ ریفل + تپانچه (hitscan, recoil, reload)
- `Enemies/enemy.gd`  هوش مصنوعی دشمن
- `Arena/arena.gd`    زمین low-poly، دیوار، سنگ، سنگر
- `Input/touch_controls.gd`  جوی‌استیک، دکمه‌ها، multi-touch، چرخش دوربین
- `UI/hud.gd`  HUD   |  `Effects/effects.gd`  جرقه و ردگلوله
- `.github/workflows/android.yml`  ساخت APK در GitHub (تست نشده)

## ساخت APK (روش کامپیوتر)
1. Godot 4.3 + Export Templates را نصب کنید.
2. JDK 17 و Android SDK (build-tools 34، platform 34، cmdline-tools) نصب کنید.
3. Editor > Editor Settings > Export > Android: مسیر SDK و debug keystore را بدهید.
4. پروژه را باز کنید > Project > Export > Android > Export Project (Debug) > `ApexArena.apk`.

## ساخت APK بدون کامپیوتر
پوشه را در یک repo گیت‌هاب آپلود کنید > تب Actions > Build Android APK > Run workflow > فایل APK در Artifacts.

## کنترل‌ها
استیک چپ = حرکت (تا لبه = sprint) | کشیدن روی صفحه راست یا روی FIRE/AIM = چرخش
SLIDE نگه‌دارید در حین دویدن = slide | JUMP حین slide = slide-jump | JUMP درست قبل/بعد از فرود = bunny hop
در slide چپ/راست = strafe و تیلت اسلحه | دکمه II = تنظیمات (اندازه HUD، جابجایی دکمه‌ها، حساسیت)
