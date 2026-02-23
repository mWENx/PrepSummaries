### Development Docs

1. Initial Python Program 
2. Claude started on the UI for flutter version 
   `claude` and described the need for a flutter app that interacts with the file system and allows excel uploads & stores last uploaded excel 
3. To run and test, do `flutter doctor` to see what you have to install 
   1. For MacM1: download xcode from app store and `brew install cocoapods` 
   2. `flutter doctor` will say your cocapods is installed but not usable but you can actually run it 
   3. If you try to `sudo gem install cocoapods` but you have `brew` managing your ruby, you will run into modification access errors and outdated ruby version errors, as the installation process for some reason references your native ruby, not the brew managed one 
4. Currently testing through `flutter run`

#### Getting this to repo

Created a new branch called `flutter-v1`

```
git init 
git remote add origin [link to our repo]
git switch -c flutter-v1
```



#### Testing Logs

Confirm what testing devices project currently supports

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

We can run simulation for the macOS version using `flutter run -d macos` 

