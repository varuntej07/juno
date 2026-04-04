import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

const ensureApp = () => {
  if (getApps().length > 0) {
    return getApps()[0]!;
  }

  return initializeApp({
    credential: applicationDefault(),
  });
};

export const adminAuth = () => getAuth(ensureApp());
export const adminFirestore = () => getFirestore(ensureApp());
export const adminMessaging = () => getMessaging(ensureApp());
