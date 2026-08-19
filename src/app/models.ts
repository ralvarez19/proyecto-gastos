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
