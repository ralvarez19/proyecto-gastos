import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';

const rules = await readFile('../../firestore.rules', 'utf8');
const environment = await initializeTestEnvironment({
  projectId: 'demo-obraflow',
  firestore: { rules },
});

try {
  const ownerDb = environment.authenticatedContext('user-a').firestore();
  const otherDb = environment.authenticatedContext('user-b').firestore();
  const guestDb = environment.unauthenticatedContext().firestore();
  const ownProject = doc(ownerDb, 'users/user-a/projects/project-1');

  await assertSucceeds(setDoc(ownProject, { name: 'Proyecto privado' }));
  const ownSnapshot = await assertSucceeds(getDoc(ownProject));
  assert.equal(ownSnapshot.data()?.['name'], 'Proyecto privado');

  await assertFails(getDoc(doc(otherDb, 'users/user-a/projects/project-1')));
  await assertFails(setDoc(doc(otherDb, 'users/user-a/projects/project-2'), { name: 'Intruso' }));
  await assertFails(getDoc(doc(guestDb, 'users/user-a/projects/project-1')));

  console.log('Reglas Firestore verificadas: aislamiento por uid correcto.');
} finally {
  await environment.cleanup();
}
