import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

/** Samma Admin-init som i övriga funktioner (`extractText` m.fl.). */
export const adminApp = getApps()[0] ?? initializeApp();

export function getDb() {
  return getFirestore(adminApp);
}

export function getDefaultBucket() {
  return getStorage(adminApp).bucket();
}
