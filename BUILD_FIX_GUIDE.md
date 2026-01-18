# 🔧 Build Fix Guide - APK Build Issues

## Current Issue
Gradle daemon is crashing during the build process. This is typically caused by memory issues or daemon conflicts.

---

## ✅ Quick Fix Steps

### Step 1: Stop All Gradle Daemons
```powershell
cd android
.\gradlew --stop
```

### Step 2: Clean Build Cache
```powershell
flutter clean
cd android
.\gradlew clean
cd ..
```

### Step 3: Delete Gradle Cache (if needed)
```powershell
# Delete gradle cache
Remove-Item -Path "$env:USERPROFILE\.gradle\caches" -Recurse -Force
Remove-Item -Path "$env:USERPROFILE\.gradle\daemon" -Recurse -Force
```

### Step 4: Rebuild
```powershell
flutter pub get
flutter build apk --release
```

---

## 🎯 Alternative Solutions

### Solution A: Build with Reduced Memory
```powershell
flutter build apk --release --no-tree-shake-icons
```

### Solution B: Build Debug APK First
```powershell
# Sometimes building debug first helps
flutter build apk --debug
# Then build release
flutter build apk --release
```

### Solution C: Build with Stack Trace
```powershell
flutter build apk --release -v
```

### Solution D: Use Split APKs (Smaller size)
```powershell
flutter build apk --split-per-abi --release
```

---

## 📋 Pre-Build Checklist

Before running build commands:

- [ ] Close Android Studio if open
- [ ] Close any running emulators
- [ ] Stop all Gradle daemons: `.\gradlew --stop`
- [ ] Run `flutter clean`
- [ ] Ensure stable internet connection
- [ ] Have at least 4GB free RAM

---

## 🔍 If Build Still Fails

### Check Java Version
```powershell
java -version
# Should show Java 11 or higher
```

### Check Flutter Doctor
```powershell
flutter doctor -v
```

### Try Building with Android Studio
1. Open project in Android Studio
2. Go to Build > Flutter > Build APK
3. Monitor memory usage in Task Manager

---

## 💾 Memory Optimization Applied

The `gradle.properties` file has been updated with:
- Reduced heap size: 2GB (was 8GB)
- Enabled parallel builds
- Enabled build caching
- Enabled R8 full mode
- Reduced metaspace

---

## 🚀 Recommended Build Command

For most reliable build:
```powershell
# 1. Clean everything
flutter clean

# 2. Stop daemons
cd android
.\gradlew --stop
cd ..

# 3. Get dependencies
flutter pub get

# 4. Build
flutter build apk --release --split-per-abi
```

This creates optimized APKs for different CPU architectures:
- `app-armeabi-v7a-release.apk` - 32-bit ARM (most phones)
- `app-arm64-v8a-release.apk` - 64-bit ARM (newer phones)
- `app-x86_64-release.apk` - 64-bit x86 (emulators)

---

## 📱 Expected Output

After successful build:
```
✓ Built build\app\outputs\flutter-apk\app-release.apk (XX.XMB)
```

APK location: `C:\i\money\build\app\outputs\flutter-apk\`

---

## ⚠️ Common Errors & Fixes

### Error: "Daemon disappeared"
**Fix:** Stop all daemons and rebuild
```powershell
cd android
.\gradlew --stop
cd ..
flutter clean
flutter build apk
```

### Error: "Out of memory"
**Fix:** Close other applications, or use split-per-abi
```powershell
flutter build apk --split-per-abi
```

### Error: "Execution failed for task"
**Fix:** Clean and get fresh dependencies
```powershell
flutter clean
flutter pub get
cd android
.\gradlew clean
cd ..
flutter build apk
```

### Error: "SDK not found"
**Fix:** Run flutter doctor and fix any issues
```powershell
flutter doctor
```

---

## 🎯 Build Size Optimization

If APK is too large:

```powershell
# 1. Use split APKs
flutter build apk --split-per-abi --release

# 2. Enable R8 shrinking (already done)
# See android/app/build.gradle.kts

# 3. Remove unused resources
flutter build apk --release --target-platform android-arm64
```

---

## 💡 Pro Tips

1. **Always use --split-per-abi** for production builds (smaller APKs)
2. **Test on real device** after building release APK
3. **Keep Gradle daemon stopped** during build to avoid conflicts
4. **Monitor memory** in Task Manager during build
5. **Close unnecessary apps** to free up RAM

---

## 📊 Build Time Expectations

- **First build:** 5-10 minutes
- **Subsequent builds:** 2-5 minutes
- **After flutter clean:** 5-10 minutes

---

## 🔗 Useful Commands

```powershell
# Check Flutter version
flutter --version

# Check Gradle version
cd android
.\gradlew --version
cd ..

# List connected devices
flutter devices

# Install APK directly
flutter install

# Build and install
flutter build apk --release && flutter install
```

---

## 📞 Still Having Issues?

If none of these solutions work:

1. **Check the crash log:**
   - Location: `C:\i\money\android\hs_err_pid*.log`
   - Look for OutOfMemoryError or other clues

2. **Restart your computer** (fresh RAM allocation)

3. **Update Flutter:**
   ```powershell
   flutter upgrade
   ```

4. **Reinstall Android SDK Tools** via Android Studio

5. **Try on different machine** (if available)

---

## ✅ Success Indicators

Build is successful when you see:
```
Running Gradle task 'assembleRelease'...
✓ Built build\app\outputs\flutter-apk\app-release.apk (XX.XMB)
```

---

## 📦 What's Next After Successful Build

1. **Test the APK:**
   ```powershell
   flutter install
   ```

2. **Transfer to phone:**
   - Connect phone via USB
   - Enable USB debugging
   - Copy APK and install

3. **Generate app bundle** (for Play Store):
   ```powershell
   flutter build appbundle --release
   ```

---

**Last Updated:** December 26, 2024  
**Flutter Version:** 3.x  
**Gradle Version:** 8.12