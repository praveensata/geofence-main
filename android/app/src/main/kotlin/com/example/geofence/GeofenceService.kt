package com.example.geofence

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.tasks.OnCompleteListener
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import com.google.firebase.Timestamp
import android.util.Log

class GeofenceService : Service() {
    private lateinit var geofencingClient: GeofencingClient
    private lateinit var geofence: Geofence
    private lateinit var sharedPreferences: SharedPreferences

    override fun onCreate() {
        super.onCreate()
        sharedPreferences = getSharedPreferences("GeofencePrefs", Context.MODE_PRIVATE)
        geofencingClient = LocationServices.getGeofencingClient(this)
        createGeofence()
        startForegroundService()
    }

    private fun createGeofence() {
        geofence = Geofence.Builder()
            .setRequestId("geoFenceId")
            .setCircularRegion(17.732036, 83.314367, 100f)
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            .build()

        val geofencingRequest = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofence(geofence)
            .build()

        val intent = Intent(this, GeofenceBroadcastReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT)

        geofencingClient.addGeofences(geofencingRequest, pendingIntent)
            .addOnCompleteListener(OnCompleteListener<Void> {
                sharedPreferences.edit().putBoolean("isGeofenceActive", true).apply()
            })
    }

    private fun startForegroundService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Geofence Service Channel", NotificationManager.IMPORTANCE_DEFAULT)
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Geofence Service")
            .setContentText("Tracking your location")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), 0))
            .build()

        startForeground(1, notification)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val isGeofenceActive = sharedPreferences.getBoolean("isGeofenceActive", false)
        if (isGeofenceActive) {
            createGeofence()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        sharedPreferences.edit().putBoolean("isGeofenceActive", false).apply()
    }

    companion object {
        private const val TAG = "GeofenceService"
        const val CHANNEL_ID = "GeofenceServiceChannel"

        fun onGeofenceTransition(context: Context, transitionType: Int) {
            if (transitionType == Geofence.GEOFENCE_TRANSITION_ENTER) {
                onEnterGeofence(context)
            } else if (transitionType == Geofence.GEOFENCE_TRANSITION_EXIT) {
                onExitGeofence(context)
            }
        }

        private fun onEnterGeofence(context: Context) {
            NotificationService.showNotification(context, "Geofence Alert", "You have entered the geofence area.")
            LogService.logBackendServiceEvent(context, "ENTER", "User entered the geofence")
            logActivity(context, "ENTER", "User entered the geofence", true)
            Log.d(TAG, "onEnterGeofence called")
        }

        private fun onExitGeofence(context: Context) {
            NotificationService.showNotification(context, "Geofence Alert", "You have exited the geofence area.")
            LogService.logBackendServiceEvent(context, "EXIT", "User exited the geofence")
            logActivity(context, "EXIT", "User exited the geofence", false)
            Log.d(TAG, "onExitGeofence called")
        }

        private fun logActivity(context: Context, activity: String, description: String, logAttendance: Boolean) {
            val user = FirebaseAuth.getInstance().currentUser ?: return
            val firestore = FirebaseFirestore.getInstance()
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val userSnapshot = firestore.collection("users").document(user.uid).get().await()
                    val customUserId = userSnapshot.getString("customUserId") ?: ""
                    val managerEmail = userSnapshot.getString("managerEmail") ?: "potti2255@gmail.com"
                    val position = LocationServices.getFusedLocationProviderClient(context).lastLocation.await()

                    val deviceModel = Build.MODEL
                    val osVersion = Build.VERSION.RELEASE

                    val data = hashMapOf(
                        "userId" to customUserId,
                        "managerEmail" to managerEmail,
                        "timestamp" to Timestamp.now(),
                        "activity" to activity,
                        "description" to description,
                        "latitude" to position.latitude,
                        "longitude" to position.longitude,
                        "deviceModel" to deviceModel,
                        "osVersion" to osVersion
                    )

                    // Log to activity_logs
                    firestore.collection("activity_logs").add(data)
                    Log.d(TAG, "Activity log added: $data")

                    // Log to backend_service_logs
                    firestore.collection("backend_service_logs").add(data)
                    Log.d(TAG, "Backend service log added: $data")

                    if (logAttendance) {
                        firestore.collection("attendance").add(
                            hashMapOf(
                                "userId" to customUserId,
                                "timestamp" to Timestamp.now(),
                                "isEntering" to (activity == "ENTER")
                            )
                        )
                        Log.d(TAG, "Attendance log added for user: $customUserId")
                    }

                    NotificationService.showNotification(context, "Geofence Alert", "Activity logged: $activity")
                } catch (e: Exception) {
                    Log.e(TAG, "Error logging activity: $e")
                }
            }
        }
    }
}
