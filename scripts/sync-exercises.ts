
import * as admin from 'firebase-admin';
import { globalExercises } from '../src/data/global-exercises';
import * as path from 'path';

// Initialize Firebase Admin
// This assumes you have exported GOOGLE_APPLICATION_CREDENTIALS or have a service-account.json in the project root
const serviceAccountPath = path.resolve(__dirname, '../service-account.json');

try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const serviceAccount = require(serviceAccountPath);
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
    console.log('Firebase Admin initialized successfully.');
} catch (error) {
    console.error('Error initializing Firebase Admin. Make sure \'service-account.json\' is in the project root.');
    console.error(error);
    process.exit(1);
}

const db = admin.firestore();

async function syncExercises() {
    const collectionRef = db.collection('globalExercises');
    console.log(`Starting sync of ${globalExercises.length} exercises...`);

    // 1. Optional: Purge existing global exercises to ensure a clean state
    // We'll read all IDs first to delete them in batches
    const snapshot = await collectionRef.get();
    if (!snapshot.empty) {
        console.log(`Deleting ${snapshot.size} existing global exercises...`);
        const batch = db.batch();
        snapshot.docs.forEach(doc => {
            batch.delete(doc.ref);
        });
        await batch.commit();
        console.log('Existing exercises deleted.');
    }

    // 2. Upload new exercises in batches of 500 (Firestore limit)
    // Since we have ~50, a loop is fine, but good practice to batch
    let batch = db.batch();
    let count = 0;
    let totalCommitted = 0;

    for (const exercise of globalExercises) {
        const docRef = collectionRef.doc(exercise.id);
        batch.set(docRef, exercise);
        count++;

        if (count >= 400) {
            await batch.commit();
            totalCommitted += count;
            console.log(`Committed batch of ${count} exercises.`);
            batch = db.batch();
            count = 0;
        }
    }

    if (count > 0) {
        await batch.commit();
        totalCommitted += count;
    }

    console.log(`Successfully synced ${totalCommitted} exercises to globalExercises collection.`);
}

syncExercises().catch(console.error);
