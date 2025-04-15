package com.example.geofence

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.LocationResult

class LocationUpdatesBroadcastReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_PROCESS_UPDATES = "com.example.geofence.ACTION_PROCESS_UPDATES"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent != null) {
            val action = intent.action
            if (ACTION_PROCESS_UPDATES == action) {
                val result = LocationResult.extractResult(intent)
                if (result != null) {
                    val locations = result.locations
                    // Handle location updates here
                    for (location in locations) {
                        // Process each location update
                    }
                }
            }
        }
    }
}
