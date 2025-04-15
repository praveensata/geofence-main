const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://geofence-18f49-default-rtdb.firebaseio.com/'
});

const db = admin.firestore();

const app = express();
app.use(cors());
app.use(bodyParser.json());

// Register new user
app.post('/register', async (req, res) => {
  const { email, password } = req.body;
  try {
    const userRecord = await admin.auth().createUser({ email, password });
    res.status(200).send({ userId: userRecord.uid });
  } catch (error) {
    res.status(500).send({ error: 'Error creating user: ' + error.message });
  }
});

// Log attendance
app.post('/logAttendance', async (req, res) => {
  const { userId, timestamp, isEntering } = req.body;
  try {
    await db.collection('attendance').add({
      userId,
      timestamp: admin.firestore.Timestamp.fromDate(new Date(timestamp)), // Store as Firestore Timestamp
      isEntering
    });
    res.status(200).send('Attendance logged successfully');
  } catch (error) {
    res.status(500).send({ error: 'Error logging attendance: ' + error.message });
  }
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
