### Development Docs

1. Initial Python Program 

2. Claude started on the UI for flutter version 
   `claude` and described the need for a flutter app that interacts with the file system and allows excel uploads & stores last uploaded excel 

3. Confirm what devices our application supports (lol)

    `flutter devices` shows: 

   ```
   Found 3 connected devices:
   macOS (desktop)  • macos  • darwin-arm64  • macOS 26.2 25C56 darwin-arm64
   Mac Designed for iPad (desktop)  • mac-designed-for-ipad  • darwin      • macOS 26.2 25C56 darwin-arm64
   Chrome (web)  • chrome  • web-javascript • Google Chrome 145.0.7632.110
   ```

   So we have connected devices we can use for testing. 

   Next, run `ls macos`, we see that we have no folder called `macos` so we need to enable it. 

   * Note that we have a folder called `ios` but that's for iphones & ipad 

   * To add macos, from root folder run `flutter create --platforms=macos` 
   * Then we can run simulation for the macOS version using `flutter run -d macos` 


4. Another obstacle before we can run. Use cmd  `flutter doctor` to see if you've satisfied all requirements

   - For MacM1: you typically have to download `xcode` from app store and install cocoapods by running `brew install cocoapods` 

   - After installing xcode, run this: 
     ```
     xcode-select -p
     sudo xcodebuild -runFirstLaunch
     ```

   - If you try to `sudo gem install cocoapods` but you have `brew` managing your ruby, you will run into modification access errors and outdated ruby version errors, as the installation process for some reason references your native ruby, not the brew managed one 

   - Brew installing cocoapods could give you this error when running `flutter doctor` or the actual app: 
     ```
     Warning: CocoaPods is installed but broken. Skipping pod install.
       You appear to have CocoaPods installed but it is not working.
       This can happen if the version of Ruby that CocoaPods was installed with is different from the one being used to invoke it.
       This can usually be fixed by re-installing CocoaPods.
     ```

   * **How to fix?** Verify that you've installed cocoapods with homebrew by running ` which -a pod`. You should see something like `/opt/homebrew/bin/pod` 

   * Check if this command returns an error: `pod --version` , and work with ChatGPT to resolve it 

   * I had a `Could not find  'ffi' (>= 1.15.0) among 118 total gem(s) ` error, which I resolved by: 
     ```
     brew install libffi
     echo 'export PATH="$HOME/.gem/ruby/4.0.0/bin:$PATH"' >> ~/.zshrc
     source ~/.zshrc
     hash -r
     ```

   * Then I ran into extensions not built issues: 
     ```
     Ignoring ffi-1.17.2 because its extensions are not built. 
     ```

     Took a few attempts to fix: 

     ```
     /opt/homebrew/opt/ruby/bin/gem pristine ffi --version 1.17.2
     /opt/homebrew/opt/ruby/bin/ruby -S gem env
     gem list ffi
     gem uninstall ffi -aIx || true
     /opt/homebrew/opt/ruby/bin/gem install ffi -v 1.17.2
     /opt/homebrew/opt/ruby/bin/gem pristine ffi --version 1.17.2
     ```

     Unfortunately didn't work: 
     ```
     Ignoring ffi-1.17.2 because its extensions are not built. 
     ```

     What worked: 

     ```
     gem pristine ffi --version 1.17.2
     
     # if something is returned after the below, your machine is confusing versions again 
     ls -d ~/.gem/ruby/4.0.0/gems/ffi-* 2>/dev/null
     ls -d ~/.gem/ruby/4.0.0/extensions/*/4.0.0/ffi-* 2>/dev/null
     
     # remove user installed versions 
     rm -rf ~/.gem/ruby/4.0.0/gems/ffi-1.17.3-arm64-darwin
     rm -f  ~/.gem/ruby/4.0.0/specifications/ffi-1.17.3-arm64-darwin.gemspec
     hash -r
     
     # verify your ruby sees ffi 
     /opt/homebrew/opt/ruby/bin/gem list ffi
     /opt/homebrew/opt/ruby/bin/gem pristine ffi --version 1.17.2
     
     # verify warning disappears 
     pod --version 
     ```

5. Back to testing. Our frontend works but no other functionality yet 
6. Prompt claude to add interaction with file systems 

   * It was already added for the other systems, just had to modify entitlement files for mac

```
⏺ Let me read the relevant files first.

⏺ Searched for 1 pattern, read 2 files (ctrl+o to expand)

⏺ The file_picker package is already in pubspec.yaml and the picker methods are already wired up. Let me check if macOS entitlements are configured correctly, since that's the most common reason file pickers silently fail on macOS.

⏺ Searched for 2 patterns, read 2 files (ctrl+o to expand)

⏺ Found the problem. The app is sandboxed but missing the com.apple.security.files.user-selected.read-write entitlement. Without it, macOS's sandbox blocks file picker access entirely — the dialog either never opens or silently returns nothing.

  I need to add this to both entitlement files:

⏺ Update(nps_app/macos/Runner/DebugProfile.entitlements)
  ⎿  Added 2 lines
       8    <true/>
       9    <key>com.apple.security.network.server</key>
      10    <true/>
      11 +  <key>com.apple.security.files.user-selected.read-write</key>  
      12 +  <true/>                                                           
      13  </dict>
      14  </plist>

⏺ Update(nps_app/macos/Runner/Release.entitlements)
  ⎿  Added 2 lines
       4  <dict>
       5    <key>com.apple.security.app-sandbox</key>
       6    <true/>
       7 +  <key>com.apple.security.files.user-selected.read-write</key>                8 +  <true/>                                                                    9  </dict>
      10  </plist>

⏺ That's the only fix needed. The buttons (_pickExcelFile, _useLastFile, _pickOutputDirectory) were already fully wired — they just couldn't open dialogs because macOS's sandbox was blocking file access.

  What changed:
  - DebugProfile.entitlements — added com.apple.security.files.user-selected.read-write
  - Release.entitlements — added com.apple.security.files.user-selected.read-write

  This entitlement grants the app permission to read/write any file the user explicitly selects through an Open or Save panel, which is exactly what FilePicker.platform.pickFiles() and getDirectoryPath() use.

  Rebuild and all three interactive buttons (Upload Excel, Use Last File, Browse Folder) will work:

  cd nps_app && flutter run -d macos
```

7. Migrated the python file's functionality over 
8. Incremental features & tweeks 

   - [x] Open last saved location instead of from root folder 
   - [x] Tweek outputted document formatting & bullet point 

     - [x] Add more details to biography bullet points 

     - [ ] Fix minor formatting errors 
   - [x] Gcal integration (add event listener for McCormick Dev Calendar)
     - [x] 不做, out of time 
   - [x] Multi-LLM Interface 
     - [x] Allow user to choose API provider / LLM 
     - [x] Allow user to choose model 
     - [x] Display estimated cost 
9. Additional tests 

   - [x] Iterative data validation 
     - [x] Need to tweak relevance 
   - [x] ==Outputting a separate "sources & quotes" document== 
   - [ ] Test with messier & missing data 
     - [ ] Usually the missing field is current employment => will have to implement more effective LinkedIn pipeline or ask user to provide it (additional UI / pop-up)
     - [ ] What if we don't find donor in the excel based on the inputted name? 
     - [ ] What if there's no LinkedIn pdf? 
     - [ ] etc. etc. 
   - [x] Experiment with n8n as an alternative
     - [x] Cost 25 dollars a month, not usable 
   - [ ] Product test with a windows device 
   - [ ] ==Publish the software so it's downloadable for the client== 


### Misc. 

#### Getting this to repo

Created a new branch called `flutter-v1`

```
git init 
git remote add origin [link to our repo]
git switch -c flutter-v1
```



