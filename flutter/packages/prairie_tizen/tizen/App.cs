using System;
using Tizen;
using Tizen.Applications;
using Tizen.Flutter.Embedding;
using Tizen.System;

namespace Runner
{
    public class App : FlutterApplication
    {
        // Must match prairie_tizen/lib/platform/tv_device_name_tizen.dart.
        private const string DeviceNameChannel = "org.prairieserver.prairie/device_name";

        // Must match prairie_tizen/lib/platform/youtube_launcher_tizen.dart.
        private const string YouTubeChannel = "org.prairieserver.prairie/youtube";

        // Samsung's YouTube app: the application ID current TVs use, then the
        // store package ID some firmware launches it by.
        private static readonly string[] YouTubeAppIds = { "9Ur5IzDKqV.TizenYouTube", "111299001912" };

        protected override void OnCreate()
        {
            base.OnCreate();

            GeneratedPluginRegistrant.RegisterPlugins(this);

            var deviceName = new MethodChannel(DeviceNameChannel);
            deviceName.SetMethodCallHandler((call) =>
            {
                if (call.Method == "getDeviceName")
                {
                    return ReadDeviceName();
                }
                throw new MissingPluginException();
            });

            var youTube = new MethodChannel(YouTubeChannel);
            youTube.SetMethodCallHandler((call) =>
            {
                if (call.Method == "openWatchPage")
                {
                    return OpenYouTubeWatchPage(call.Arguments as string);
                }
                throw new MissingPluginException();
            });
        }

        // Opens the video in the TV's YouTube app at its watch-page link, the
        // form Android TV integrations use to start a specific video (Android
        // #600). The link goes in the app control's URI; Samsung's YouTube
        // app reads the video from PAYLOAD, so that carries it too. Returns
        // false when no YouTube app takes the launch, and Dart offers a QR
        // code instead. Needs the appmanager.launch privilege.
        private static bool OpenYouTubeWatchPage(string videoId)
        {
            if (string.IsNullOrWhiteSpace(videoId))
            {
                return false;
            }
            var watchUrl = "https://www.youtube.com/watch?v=" + Uri.EscapeDataString(videoId);
            foreach (var appId in YouTubeAppIds)
            {
                try
                {
                    var control = new AppControl
                    {
                        ApplicationId = appId,
                        Operation = AppControlOperations.View,
                        Uri = watchUrl,
                    };
                    control.ExtraData.Add("PAYLOAD", "#play=" + videoId);
                    AppControl.SendLaunchRequest(control);
                    return true;
                }
                catch (Exception e)
                {
                    Log.Warn("Prairie", "YouTube launch via " + appId + " failed: " + e.Message);
                }
            }
            return false;
        }

        // The name the owner gave the TV in its settings. Reading it needs no
        // privilege; profiles without the key throw NotSupportedException, so
        // any failure returns null and Dart falls back to the generic name.
        private static string ReadDeviceName()
        {
            try
            {
                return SystemSettings.DeviceName;
            }
            catch (Exception e)
            {
                Log.Warn("Prairie", "SystemSettings.DeviceName unavailable: " + e.Message);
                return null;
            }
        }

        static void Main(string[] args)
        {
            var app = new App();
            app.Run(args);
        }
    }
}
