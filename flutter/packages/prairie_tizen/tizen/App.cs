using System;
using Tizen;
using Tizen.Flutter.Embedding;
using Tizen.System;

namespace Runner
{
    public class App : FlutterApplication
    {
        // Must match prairie_tizen/lib/platform/tv_device_name_tizen.dart.
        private const string DeviceNameChannel = "org.prairieserver.prairie/device_name";

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
