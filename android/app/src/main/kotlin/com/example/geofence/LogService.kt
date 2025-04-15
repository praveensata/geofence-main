package com.example.geofence

import android.content.Context
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.Timestamp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import com.google.android.gms.location.LocationServices

object LogService {

    private const val TAG = "LogService"

    fun logBackendServiceEvent(context: Context, event: String, description: String) {
        val user = FirebaseAuth.getInstance().currentUser
        if (user == null) {
            Log.e(TAG, "User is not authenticated")
            return
        }

        val firestore = FirebaseFirestore.getInstance()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val position = LocationServices.getFusedLocationProviderClient(context).lastLocation.await()
                val data = hashMapOf(
                    "userId" to user.uid,
                    "event" to event,
                    "description" to description,
                    "timestamp" to Timestamp.now(),
                    "latitude" to position.latitude,
                    "longitude" to position.longitude
                )

                firestore.collection("backend_service_logs").add(data)
                Log.d(TAG, "Backend service log added: $data")
            } catch (e: Exception) {
                Log.e(TAG, "Error logging backend service event: $e")
            }
        }
    }
}
