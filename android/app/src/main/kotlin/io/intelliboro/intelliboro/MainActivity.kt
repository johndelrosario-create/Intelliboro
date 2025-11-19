package io.intelliboro.intelliboro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "location_monitor"
    private var locationReceiver: BroadcastReceiver? = null
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startLocationMonitoring" -> {
                    startLocationMonitoring()
                    result.success(true)
                }
                "stopLocationMonitoring" -> {
                    stopLocationMonitoring()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startLocationMonitoring() {
        if (locationReceiver != null) {
            // Already monitoring
            return
        }

        locationReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == LocationManager.PROVIDERS_CHANGED_ACTION) {
                    checkLocationStatus()
                }
            }
        }

        val filter = IntentFilter(LocationManager.PROVIDERS_CHANGED_ACTION)
        // Register receiver on the application context so it survives activity
        // lifecycle events while the app process remains alive.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            applicationContext.registerReceiver(locationReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            applicationContext.registerReceiver(locationReceiver, filter)
        }

        // Check initial status
        checkLocationStatus()
    }

    private fun stopLocationMonitoring() {
        locationReceiver?.let {
            try {
                // Unregister from application context to match registration
                applicationContext.unregisterReceiver(it)
            } catch (e: Exception) {
                // Receiver not registered or already unregistered
            }
            locationReceiver = null
        }
    }

    private fun checkLocationStatus() {
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val isGpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
        val isNetworkEnabled = locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        
        val isLocationEnabled = isGpsEnabled || isNetworkEnabled

        // Notify Flutter about location status change
        methodChannel?.invokeMethod("onLocationStatusChanged", isLocationEnabled)
    }

    override fun onDestroy() {
        stopLocationMonitoring()
        super.onDestroy()
    }
}
