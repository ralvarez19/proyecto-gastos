import { Injectable, signal } from '@angular/core';
import {
  GoogleAuthProvider,
  User,
  createUserWithEmailAndPassword,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut,
} from 'firebase/auth';

import { firebaseAuth } from './firebase.client';

@Injectable({ providedIn: 'root' })
export class AuthService {
  readonly user = signal<User | null>(null);
  readonly ready = signal(false);

  constructor() {
    onAuthStateChanged(firebaseAuth, (user) => {
      this.user.set(user);
      this.ready.set(true);
    });
  }

  signIn(email: string, password: string) {
    return signInWithEmailAndPassword(firebaseAuth, email, password);
  }

  register(email: string, password: string) {
    return createUserWithEmailAndPassword(firebaseAuth, email, password);
  }

  signInWithGoogle() {
    return signInWithPopup(firebaseAuth, new GoogleAuthProvider());
  }

  signOut() {
    return signOut(firebaseAuth);
  }
}
