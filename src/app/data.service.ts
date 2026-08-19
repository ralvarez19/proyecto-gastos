import { Injectable, signal } from '@angular/core';
import {
  Unsubscribe,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  onSnapshot,
  serverTimestamp,
  setDoc,
  writeBatch,
} from 'firebase/firestore';

import { firestore } from './firebase.client';
import { Category, Expense, Project, Supplier, UserSeed } from './models';

export type SyncState = 'idle' | 'syncing' | 'synced' | 'offline' | 'error';

interface SyncHandlers {
  projects: (items: Project[]) => void;
  expenses: (items: Expense[]) => void;
  categories: (items: Category[]) => void;
  suppliers: (items: Supplier[]) => void;
  vatRate: (value: number) => void;
}

interface CategoryCache {
  fetchedAt: string;
  items: Category[];
}

@Injectable({ providedIn: 'root' })
export class DataService {
  readonly syncState = signal<SyncState>('idle');
  readonly syncError = signal('');
  readonly categoriesFetchedAt = signal<Date | null>(null);
  private subscriptions: Unsubscribe[] = [];
  private categoryHandler?: (items: Category[]) => void;
  private connectedUid = '';

  async connect(uid: string, email: string | null, seed: UserSeed, handlers: SyncHandlers) {
    this.disconnect();
    this.connectedUid = uid;
    this.categoryHandler = handlers.categories;
    this.syncState.set('syncing');
    this.syncError.set('');
    await this.initializeUser(uid, email, seed);
    await this.ensureActualInvoiceSeed(uid, seed);
    await this.refreshCategories(uid, false);

    this.subscriptions.push(
      onSnapshot(
        collection(firestore, 'users', uid, 'projects'),
        { includeMetadataChanges: true },
        (snapshot) => {
          handlers.projects(snapshot.docs.map((item) => item.data() as Project));
          this.updateState(snapshot.metadata.fromCache);
        },
        (error) => this.fail(error),
      ),
      onSnapshot(
        collection(firestore, 'users', uid, 'expenses'),
        { includeMetadataChanges: true },
        (snapshot) => {
          const items = snapshot.docs.map((item) => item.data() as Expense);
          handlers.expenses(items.sort((a, b) => b.date.localeCompare(a.date)));
          this.updateState(snapshot.metadata.fromCache);
        },
        (error) => this.fail(error),
      ),
      onSnapshot(
        collection(firestore, 'users', uid, 'providers'),
        { includeMetadataChanges: true },
        (snapshot) => {
          handlers.suppliers(
            snapshot.docs
              .map((item) => item.data() as Supplier)
              .sort((a, b) => a.name.localeCompare(b.name)),
          );
          this.updateState(snapshot.metadata.fromCache);
        },
        (error) => this.fail(error),
      ),
      onSnapshot(
        doc(firestore, 'users', uid, 'settings', 'general'),
        { includeMetadataChanges: true },
        (snapshot) => {
          if (snapshot.exists()) handlers.vatRate(Number(snapshot.data()['vatRate'] ?? 15));
          this.updateState(snapshot.metadata.fromCache);
        },
        (error) => this.fail(error),
      ),
    );
  }

  disconnect() {
    for (const unsubscribe of this.subscriptions) unsubscribe();
    this.subscriptions = [];
    this.categoryHandler = undefined;
    this.connectedUid = '';
    this.syncState.set('idle');
  }

  saveProject(uid: string, project: Project) {
    return this.write(setDoc(doc(firestore, 'users', uid, 'projects', project.id), {
      ...project,
      updatedAt: serverTimestamp(),
    }));
  }

  saveExpense(uid: string, expense: Expense) {
    return this.write(setDoc(doc(firestore, 'users', uid, 'expenses', expense.id), {
      ...expense,
      updatedAt: serverTimestamp(),
    }));
  }

  deleteExpense(uid: string, expenseId: string) {
    return this.write(deleteDoc(doc(firestore, 'users', uid, 'expenses', expenseId)));
  }

  async saveCategory(uid: string, category: Category) {
    await this.write(setDoc(doc(firestore, 'users', uid, 'categories', category.id), {
      ...category,
      updatedAt: serverTimestamp(),
    }));
    await this.refreshCategories(uid, true);
  }

  async deleteCategory(uid: string, categoryId: string) {
    await this.write(deleteDoc(doc(firestore, 'users', uid, 'categories', categoryId)));
    await this.refreshCategories(uid, true);
  }

  async refreshCategories(uid = this.connectedUid, force = true) {
    if (!uid) return;
    const cacheKey = `obraflow-categories-${uid}`;
    if (!force) {
      const cached = this.readCategoryCache(cacheKey);
      if (cached && Date.now() - new Date(cached.fetchedAt).getTime() < 86_400_000) {
        this.categoriesFetchedAt.set(new Date(cached.fetchedAt));
        this.categoryHandler?.(cached.items);
        return;
      }
    }
    this.syncState.set('syncing');
    const snapshot = await getDocs(collection(firestore, 'users', uid, 'categories'));
    const items = snapshot.docs
      .map((item) => item.data() as Category)
      .filter((item) => item.name)
      .sort((a, b) => a.name.localeCompare(b.name));
    const fetchedAt = new Date();
    localStorage.setItem(cacheKey, JSON.stringify({ fetchedAt: fetchedAt.toISOString(), items }));
    this.categoriesFetchedAt.set(fetchedAt);
    this.categoryHandler?.(items);
    this.syncState.set('synced');
  }

  saveSupplier(uid: string, supplier: Supplier) {
    return this.write(setDoc(doc(firestore, 'users', uid, 'providers', supplier.id), {
      ...supplier,
      updatedAt: serverTimestamp(),
    }));
  }

  deleteSupplier(uid: string, supplierId: string) {
    return this.write(deleteDoc(doc(firestore, 'users', uid, 'providers', supplierId)));
  }

  saveVatRate(uid: string, vatRate: number) {
    return this.write(setDoc(
      doc(firestore, 'users', uid, 'settings', 'general'),
      { vatRate, updatedAt: serverTimestamp() },
      { merge: true },
    ));
  }

  private async initializeUser(uid: string, email: string | null, seed: UserSeed) {
    const userRef = doc(firestore, 'users', uid);
    const current = await getDoc(userRef);
    if (current.exists()) return;
    const batch = writeBatch(firestore);
    batch.set(userRef, { uid, email, createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    for (const project of seed.projects)
      batch.set(doc(firestore, 'users', uid, 'projects', project.id), project);
    for (const expense of seed.expenses)
      batch.set(doc(firestore, 'users', uid, 'expenses', expense.id), expense);
    for (const category of seed.categories)
      batch.set(doc(firestore, 'users', uid, 'categories', category.id), category);
    for (const supplier of seed.suppliers)
      batch.set(doc(firestore, 'users', uid, 'providers', supplier.id), supplier);
    batch.set(doc(firestore, 'users', uid, 'settings', 'general'), {
      vatRate: seed.vatRate,
      updatedAt: serverTimestamp(),
    });
    await batch.commit();
  }

  private async ensureActualInvoiceSeed(uid: string, seed: UserSeed) {
    const marker = doc(firestore, 'users', uid, 'settings', 'import-real-invoices-v1');
    if ((await getDoc(marker)).exists()) return;
    const batch = writeBatch(firestore);
    for (const id of ['e1', 'e2', 'e3', 'demo-cemento', 'demo-albaniles', 'demo-transporte', 'demo-hierro', 'demo-arena'])
      batch.delete(doc(firestore, 'users', uid, 'expenses', id));
    for (const id of ['p1', 'p2', 'p3', 'project-ceibos', 'project-sambo', 'project-olon'])
      batch.delete(doc(firestore, 'users', uid, 'projects', id));
    for (const project of seed.projects)
      batch.set(doc(firestore, 'users', uid, 'projects', project.id), { ...project, updatedAt: serverTimestamp() });
    for (const expense of seed.expenses)
      batch.set(doc(firestore, 'users', uid, 'expenses', expense.id), { ...expense, updatedAt: serverTimestamp() });
    for (const category of seed.categories)
      batch.set(doc(firestore, 'users', uid, 'categories', category.id), { ...category, updatedAt: serverTimestamp() });
    for (const supplier of seed.suppliers)
      batch.set(doc(firestore, 'users', uid, 'providers', supplier.id), { ...supplier, updatedAt: serverTimestamp() });
    batch.set(marker, { importedAt: serverTimestamp(), source: 'facturas-2026-08-15' });
    await batch.commit();
    localStorage.removeItem(`obraflow-categories-${uid}`);
  }

  private readCategoryCache(key: string): CategoryCache | null {
    try {
      return JSON.parse(localStorage.getItem(key) ?? '') as CategoryCache;
    } catch {
      return null;
    }
  }

  private async write(operation: Promise<unknown>) {
    this.syncState.set('syncing');
    this.syncError.set('');
    try {
      await operation;
    } catch (error) {
      this.fail(error);
      throw error;
    }
  }

  private updateState(fromCache: boolean) {
    if (this.syncState() !== 'error') this.syncState.set(fromCache ? 'offline' : 'synced');
  }

  private fail(error: unknown) {
    this.syncState.set('error');
    this.syncError.set((error as { message?: string }).message ?? 'Error de sincronización');
  }
}
