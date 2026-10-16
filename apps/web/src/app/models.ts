export type ProjectStatus = 'ACTIVE' | 'PAUSED' | 'COMPLETED';

export interface Project {
  id: string;
  name: string;
  location: string;
  budget: number;
  progress: number;
  status: ProjectStatus;
}

export interface Expense {
  id: string;
  projectId: string;
  category: string;
  description: string;
  provider: string;
  invoiceNumber: string;
  quantity: number;
  unitPrice: number;
  subtotal: number;
  taxRate: number;
  tax: number;
  total: number;
  date: string;
}

export interface Category {
  id: string;
  name: string;
}

export interface Supplier {
  id: string;
  name: string;
  contact: string;
  phone: string;
}

export interface UserSeed {
  projects: Project[];
  expenses: Expense[];
  categories: Category[];
  suppliers: Supplier[];
  vatRate: number;
}

export type WorkerStatus = 'ACTIVE' | 'INACTIVE';
export type AttendanceStatus = 'FULL' | 'HALF' | 'ABSENT' | 'REST';

export interface Worker {
  id: string;
  fullName: string;
  nationalId: string;
  phone: string;
  roleId: string;
  defaultRate: number;
  startDate: string;
  status: WorkerStatus;
  notes: string;
  projectIds: string[];
  updatedAt?: unknown;
}

export interface WorkerRole {
  id: string;
  name: string;
  active: boolean;
}

export interface WorkerRate {
  id: string;
  workerId: string;
  projectId: string;
  dailyRate: number;
  validFrom: string;
  validTo: string;
}

export interface WorkerAttendance {
  id: string;
  workerId: string;
  projectId: string;
  date: string;
  status: AttendanceStatus;
  appliedRate: number;
  allocation: number;
  earned: number;
  notes: string;
  revision: number;
}

export interface WorkerAdvance {
  id: string;
  workerId: string;
  projectId: string;
  date: string;
  amount: number;
  method: 'CASH' | 'TRANSFER';
  reference: string;
  notes: string;
  appliedAmount: number;
}

export interface WorkerPayment {
  id: string;
  workerId: string;
  projectId: string;
  periodStart: string;
  periodEnd: string;
  date: string;
  amount: number;
  method: 'CASH' | 'TRANSFER';
  reference: string;
  notes: string;
}
