package com.example.geofence

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

class GeofenceBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        val geofencingEvent = intent?.let { GeofencingEvent.fromIntent(it) }
        if (geofencingEvent?.hasError() == true) {
            // Handle error
            return
        }

        val geofenceTransition = geofencingEvent?.geofenceTransition
        if (geofenceTransition == Geofence.GEOFENCE_TRANSITION_ENTER) {
            GeofenceService.onGeofenceTransition(context!!, Geofence.GEOFENCE_TRANSITION_ENTER)
        } else if (geofenceTransition == Geofence.GEOFENCE_TRANSITION_EXIT) {
            GeofenceService.onGeofenceTransition(context!!, Geofence.GEOFENCE_TRANSITION_EXIT)
        }
    }
}
