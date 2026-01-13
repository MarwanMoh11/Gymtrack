
import * as admin from 'firebase-admin';
import * as path from 'path';

// Initialize Firebase Admin
const serviceAccountPath = path.resolve(__dirname, '../service-account.json');

try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const serviceAccount = require(serviceAccountPath);
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
} catch (error) {
    console.error('Error initializing Firebase Admin. Make sure \'service-account.json\' is in the project root.');
    process.exit(1);
}

const db = admin.firestore();

async function purgeUserData() {
    console.log('WARNING: This script will DELETE ALL USER DATA (Plans, Logs, Profiles).');
    console.log('Starting purge in 5 seconds... Press Ctrl+C to cancel.');

    await new Promise(resolve => setTimeout(resolve, 5000));

    const usersRef = db.collection('users');
    const snapshot = await usersRef.get();

    if (snapshot.empty) {
        console.log('No users found to purge.');
        return;
    }

    console.log(`Found ${snapshot.size} users. Deleting data...`);

    // Function to delete all documents in a collection recursively
    // Firestore Admin doesn't recursively delete subcollections automatically in all environments,
    // so we should ideally use the tools/firebase CLI, but for a script we try best effort.
    // Actually, for a robust purge, we need to list subcollections (dailyLogs) for each user.

    for (const userDoc of snapshot.docs) {
        const userId = userDoc.id;
        console.log(`Processing user: ${userId}`);

        // 1. Delete dailyLogs subcollection
        const logsRef = usersRef.doc(userId).collection('dailyLogs');
        const logsSnapshot = await logsRef.get();

        if (!logsSnapshot.empty) {
            const batch = db.batch();
            logsSnapshot.docs.forEach(doc => batch.delete(doc.ref));
            await batch.commit();
            console.log(`  - Deleted ${logsSnapshot.size} log entries.`);
        }

        // 2. Delete the user document itself
        await userDoc.ref.delete();
        console.log(`  - Deleted user profile.`);
    }

    console.log('Purge complete.');
}

purgeUserData().catch(console.error);
