import { CommonModule } from '@angular/common';
import { Component, effect, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AuthService } from './auth.service';
import { DataService } from './data.service';
import { calculateEarned, summarizeLabor } from './labor-calculator';
import {
  Category, Expense, Project, ProjectStatus, Supplier, UserSeed,
  Worker, WorkerAdvance, WorkerAttendance, WorkerPayment, WorkerRate, WorkerRole,
} from './models';

type Tab = 'inicio' | 'proyectos' | 'gastos' | 'personal' | 'proveedores' | 'reportes' | 'mas';
type LaborView = 'dashboard' | 'workers' | 'attendance' | 'advances' | 'payroll';

const PROJECTS: Project[] = [
  {
    id: 'project-real-unassigned',
    name: 'Por asignar',
    location: 'Pendiente de definir',
    budget: 0,
    progress: 0,
    status: 'ACTIVE',
  },
];
const EXPENSES: Expense[] = [
  {
    id: 'real-fac1-01',
    projectId: 'project-real-unassigned',
    invoiceNumber: '001-020-000380000',
    category: 'Materiales · Acero',
    description: 'Hierro Adelca 10 x 12 mm',
    provider: 'Su Ferretero - Construcciones Cranbegal Cía. Ltda.',
    quantity: 96,
    unitPrice: 6.735396,
    subtotal: 646.59,
    taxRate: 5,
    tax: 32.33,
    total: 678.92,
    date: '2026-08-15',
  },
  {
    id: 'real-fac1-02',
    projectId: 'project-real-unassigned',
    invoiceNumber: '001-020-000380000',
    category: 'Materiales · Acero',
    description: 'Hierro Adelca 12 x 12 mm',
    provider: 'Su Ferretero - Construcciones Cranbegal Cía. Ltda.',
    quantity: 207,
    unitPrice: 9.701,
    subtotal: 2008.11,
    taxRate: 5,
    tax: 100.41,
    total: 2108.52,
    date: '2026-08-15',
  },
  {
    id: 'real-fac1-03',
    projectId: 'project-real-unassigned',
    invoiceNumber: '001-020-000380000',
    category: 'Materiales · Acero',
    description: 'Hierro Adelca 14 x 12 m',
    provider: 'Su Ferretero - Construcciones Cranbegal Cía. Ltda.',
    quantity: 147,
    unitPrice: 13.197599,
    subtotal: 1940.05,
    taxRate: 15,
    tax: 291.01,
    total: 2231.06,
    date: '2026-08-15',
  },
  {
    id: 'real-fac1-04',
    projectId: 'project-real-unassigned',
    invoiceNumber: '001-020-000380000',
    category: 'Materiales · Acero',
    description: 'Rollo de alambre #18 galvanizado',
    provider: 'Su Ferretero - Construcciones Cranbegal Cía. Ltda.',
    quantity: 5,
    unitPrice: 28.8134,
    subtotal: 144.07,
    taxRate: 15,
    tax: 21.61,
    total: 165.68,
    date: '2026-08-15',
  },
  {
    id: 'real-fac1-05',
    projectId: 'project-real-unassigned',
    invoiceNumber: '001-020-000380000',
    category: 'Herramientas · Consumibles',
    description: 'Disco de corte para hierro Norton',
    provider: 'Su Ferretero - Construcciones Cranbegal Cía. Ltda.',
    quantity: 10,
    unitPrice: 2.1856,
    subtotal: 21.86,
    taxRate: 15,
    tax: 3.27,
    total: 25.13,
    date: '2026-08-15',
  },
  {
    id: 'real-fac2-01',
    projectId: 'project-real-unassigned',
    invoiceNumber: '001-020-000380009',
    category: 'Herramientas · Manuales',
    description: 'Martillo Truper 16 oz',
    provider: 'Su Ferretero - Construcciones Cranbegal Cía. Ltda.',
    quantity: 1,
    unitPrice: 9.999,
    subtotal: 10,
    taxRate: 15,
    tax: 1.5,
    total: 11.5,
    date: '2026-08-15',
  },
  {
    id: 'real-fac2-02',
    projectId: 'project-real-unassigned',
    invoiceNumber: '001-020-000380009',
    category: 'Herramientas · Manuales',
    description: 'Alicate Stanley original',
    provider: 'Su Ferretero - Construcciones Cranbegal Cía. Ltda.',
    quantity: 1,
    unitPrice: 7.623,
    subtotal: 7.62,
    taxRate: 15,
    tax: 1.15,
    total: 8.77,
    date: '2026-08-15',
  },
  {
    id: 'real-fac2-03',
    projectId: 'project-real-unassigned',
    invoiceNumber: '001-020-000380009',
    category: 'Herramientas · Manuales',
    description: 'Flexómetro Truper 3 m',
    provider: 'Su Ferretero - Construcciones Cranbegal Cía. Ltda.',
    quantity: 1,
    unitPrice: 4.578,
    subtotal: 4.58,
    taxRate: 15,
    tax: 0.68,
    total: 5.26,
    date: '2026-08-15',
  },
];

const CATEGORIES: Category[] = [
  { id: 'cat-real-acero', name: 'Materiales · Acero' },
  { id: 'cat-real-consumibles', name: 'Herramientas · Consumibles' },
  { id: 'cat-real-manuales', name: 'Herramientas · Manuales' },
];

const SUPPLIERS: Supplier[] = [
  {
    id: 'provider-su-ferretero',
    name: 'Su Ferretero - Construcciones Cranbegal Cía. Ltda.',
    contact: '',
    phone: '',
  },
];

const DEFAULT_ROLES: WorkerRole[] = [
  'Maestro de obra', 'Albañil', 'Ayudante', 'Electricista', 'Plomero', 'Pintor',
  'Soldador', 'Carpintero', 'Operador de maquinaria', 'Otros',
].map((name) => ({ id: name.toLocaleLowerCase('es').replace(/\s+/g, '-'), name, active: true }));

@Component({
  selector: 'app-root',
  imports: [CommonModule, FormsModule],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  readonly auth = inject(AuthService);
  readonly data = inject(DataService);
  loginEmail = '';
  loginPassword = '';
  authError = '';
  authLoading = false;
  tab: Tab = 'inicio';
  filter: ProjectStatus | 'ALL' = 'ACTIVE';
  projects: Project[] = structuredClone(PROJECTS);
  expenses: Expense[] = structuredClone(EXPENSES);
  vatRate = Number(localStorage.getItem('obraflow-vat') ?? 15);
  reportEnd = this.todayLocal();
  reportStart = this.oneMonthBefore(this.reportEnd);
  expenseSearch = '';
  expenseProjectFilter = 'ALL';
  projectDialog = false;
  expenseDialog = false;
  editingProjectId = '';
  editingExpenseId = '';
  projectDraft: Project = this.emptyProject();
  expenseDraft: Expense = this.emptyExpense();
  categories: Category[] = structuredClone(CATEGORIES);
  suppliers: Supplier[] = structuredClone(SUPPLIERS);
  newCategory = '';
  editingCategoryId = '';
  supplierDialog = false;
  editingSupplierId = '';
  supplierDraft: Supplier = this.emptySupplier();
  laborView: LaborView = 'dashboard';
  workers: Worker[] = [];
  workerRoles: WorkerRole[] = structuredClone(DEFAULT_ROLES);
  workerRates: WorkerRate[] = [];
  attendance: WorkerAttendance[] = [];
  advances: WorkerAdvance[] = [];
  workerPayments: WorkerPayment[] = [];
  workerDialog = false;
  attendanceDialog = false;
  advanceDialog = false;
  paymentDialog = false;
  editingWorkerId = '';
  workerDraft: Worker = this.emptyWorker();
  attendanceDraft: WorkerAttendance = this.emptyAttendance();
  advanceDraft: WorkerAdvance = this.emptyAdvance();
  paymentDraft: WorkerPayment = this.emptyPayment();
  newWorkerRole = '';
  laborProjectFilter = 'ALL';
  laborPeriodStart = this.startOfWeek();
  laborPeriodEnd = this.endOfWeek();
  private activeDataUid = '';
  private readonly legacySeed: UserSeed = {
    projects: structuredClone(this.projects),
    expenses: structuredClone(this.expenses),
    categories: structuredClone(this.categories),
    suppliers: structuredClone(SUPPLIERS),
    vatRate: this.vatRate,
  };

  constructor() {
    effect(() => {
      const user = this.auth.user();
      if (!user) {
        this.data.disconnect();
        this.activeDataUid = '';
        return;
      }
      if (this.activeDataUid !== user.uid) {
        void this.connectUserData(user.uid, user.email);
      }
    });
  }

  get filteredProjects() {
    return this.filter === 'ALL'
      ? this.projects
      : this.projects.filter((p) => p.status === this.filter);
  }
  get activeProjects() {
    return this.projects.filter((p) => p.status === 'ACTIVE');
  }
  get activeExpenses() {
    const ids = new Set(this.activeProjects.map((p) => p.id));
    return this.expenses.filter((e) => ids.has(e.projectId));
  }
  get filteredActiveExpenses() {
    const query = this.expenseSearch.trim().toLocaleLowerCase('es');
    return this.activeExpenses.filter((expense) => {
      if (this.expenseProjectFilter !== 'ALL' && expense.projectId !== this.expenseProjectFilter)
        return false;
      if (!query) return true;
      return [
        expense.description,
        expense.invoiceNumber,
        expense.category,
        expense.provider,
        this.projectName(expense.projectId),
      ].some((value) => value.toLocaleLowerCase('es').includes(query));
    });
  }
  get filteredExpenseTotal() {
    return this.filteredActiveExpenses.reduce((sum, expense) => sum + expense.total, 0);
  }
  get filteredExpenseTax() {
    return this.filteredActiveExpenses.reduce((sum, expense) => sum + expense.tax, 0);
  }
  get visibleExpenses() {
    const ids = new Set(this.filteredProjects.map((p) => p.id));
    return this.expenses.filter((e) => ids.has(e.projectId));
  }
  get budget() {
    return this.filteredProjects.reduce((s, p) => s + p.budget, 0);
  }
  get spent() {
    const ids = new Set(this.filteredProjects.map((project) => project.id));
    return this.visibleExpenses.reduce((s, e) => s + e.total, 0) + this.attendance.filter((item) => ids.has(item.projectId)).reduce((sum, item) => sum + item.earned, 0);
  }
  get taxTotal() {
    return this.visibleExpenses.reduce((s, e) => s + e.tax, 0);
  }
  get activeSpent() {
    const ids = new Set(this.activeProjects.map((project) => project.id));
    return this.activeExpenses.reduce((s, e) => s + e.total, 0) + this.attendance.filter((item) => ids.has(item.projectId)).reduce((sum, item) => sum + item.earned, 0);
  }
  get monthlyExpenses() {
    return this.activeExpenses.filter(
      (expense) => expense.date >= this.reportStart && expense.date <= this.reportEnd,
    );
  }
  get monthlyTotal() {
    return this.monthlyExpenses.reduce((sum, expense) => sum + expense.total, 0);
  }
  get monthlyTax() {
    return this.monthlyExpenses.reduce((sum, expense) => sum + expense.tax, 0);
  }
  get monthlyInvoiceCount() {
    return new Set(this.monthlyExpenses.map((expense) => expense.invoiceNumber).filter(Boolean))
      .size;
  }
  get monthlyCategorySummary() {
    const totals = new Map<string, number>();
    for (const expense of this.monthlyExpenses)
      totals.set(expense.category, (totals.get(expense.category) ?? 0) + expense.total);
    return [...totals.entries()].map(([category, total]) => ({ category, total }));
  }
  get activeWorkers() { return this.workers.filter((worker) => worker.status === 'ACTIVE'); }
  get periodAttendance() {
    return this.attendance.filter((item) => item.date >= this.laborPeriodStart && item.date <= this.laborPeriodEnd && (this.laborProjectFilter === 'ALL' || item.projectId === this.laborProjectFilter));
  }
  get periodAdvances() {
    return this.advances.filter((item) => item.date >= this.laborPeriodStart && item.date <= this.laborPeriodEnd && (this.laborProjectFilter === 'ALL' || item.projectId === this.laborProjectFilter));
  }
  get periodPayments() {
    return this.workerPayments.filter((item) => item.date >= this.laborPeriodStart && item.date <= this.laborPeriodEnd && (this.laborProjectFilter === 'ALL' || item.projectId === this.laborProjectFilter));
  }
  get laborSummary() { return summarizeLabor(this.periodAttendance, this.periodAdvances, this.periodPayments); }
  get laborByWorker() {
    return this.workers.map((worker) => ({ worker, summary: summarizeLabor(
      this.periodAttendance.filter((item) => item.workerId === worker.id),
      this.periodAdvances.filter((item) => item.workerId === worker.id),
      this.periodPayments.filter((item) => item.workerId === worker.id),
    )})).filter((item) => item.summary.earned || item.summary.advances || item.summary.payments);
  }
  get todayLabor() { return this.attendance.filter((item) => item.date === this.todayLocal()).reduce((sum, item) => sum + item.earned, 0); }
  get monthLabor() { const month = this.todayLocal().slice(0, 7); return this.attendance.filter((item) => item.date.startsWith(month)).reduce((sum, item) => sum + item.earned, 0); }
  laborForProject(id: string) { return this.attendance.filter((item) => item.projectId === id).reduce((sum, item) => sum + item.earned, 0); }
  workerName(id: string) { return this.workers.find((worker) => worker.id === id)?.fullName ?? 'Trabajador'; }
  roleName(id: string) { return this.workerRoles.find((role) => role.id === id)?.name ?? 'Otros'; }
  get syncLabel() {
    return {
      idle: 'Sin conexión',
      syncing: 'Sincronizando…',
      synced: 'Sincronizado',
      offline: 'Modo offline',
      error: 'Error de sincronización',
    }[this.data.syncState()];
  }
  projectName(id: string) {
    return this.projects.find((p) => p.id === id)?.name ?? 'Proyecto';
  }
  projectSpent(id: string) {
    return this.expenses.filter((e) => e.projectId === id).reduce((s, e) => s + e.total, 0) + this.laborForProject(id);
  }
  statusLabel(status: ProjectStatus) {
    return { ACTIVE: 'Activo', PAUSED: 'Pausado', COMPLETED: 'Completado' }[status];
  }
  money(value: number) {
    return new Intl.NumberFormat('es-EC', { style: 'currency', currency: 'USD' }).format(value);
  }

  async signIn() {
    if (!this.validateCredentials()) return;
    await this.runAuth(() => this.auth.signIn(this.loginEmail.trim(), this.loginPassword));
  }

  async register() {
    if (!this.validateCredentials()) return;
    await this.runAuth(() => this.auth.register(this.loginEmail.trim(), this.loginPassword));
  }

  async signInWithGoogle() {
    await this.runAuth(() => this.auth.signInWithGoogle());
  }

  async signOut() {
    await this.auth.signOut();
    this.loginPassword = '';
  }

  openProject(project?: Project) {
    this.editingProjectId = project?.id ?? '';
    this.projectDraft = project ? { ...project } : this.emptyProject();
    this.projectDialog = true;
  }
  async saveProject() {
    if (!this.projectDraft.name.trim() || this.projectDraft.budget <= 0) return;
    const project = {
      ...this.projectDraft,
      id: this.editingProjectId || crypto.randomUUID(),
    };
    await this.data.saveProject(this.requireUid(), project);
    this.projectDialog = false;
  }
  async toggleProject(project: Project) {
    const next: ProjectStatus = project.status === 'PAUSED' ? 'ACTIVE' : 'PAUSED';
    if (
      !confirm(
        next === 'PAUSED'
          ? `¿Pausar ${project.name}? Dejará de aparecer en Gastos y Reportes.`
          : `¿Reactivar ${project.name}?`,
      )
    )
      return;
    await this.data.saveProject(this.requireUid(), { ...project, status: next });
  }
  async deleteProject(project: Project) {
    const expenseCount = this.expenses.filter((expense) => expense.projectId === project.id).length;
    if (expenseCount > 0) {
      alert(
        `${project.name} tiene ${expenseCount} gasto(s) asociado(s). Para proteger tus datos reales, mueve esos gastos a otro proyecto antes de eliminarlo.`,
      );
      return;
    }
    if (
      !confirm(
        `¿Eliminar el proyecto “${project.name}”? Esta acción solo está disponible porque no tiene gastos asociados.`,
      )
    )
      return;
    const deleted = await this.data.deleteProject(this.requireUid(), project.id);
    if (!deleted)
      alert(
        'No se eliminó el proyecto porque ahora tiene gastos asociados. Actualiza e inténtalo nuevamente.',
      );
  }
  openExpense(expense?: Expense) {
    if (!this.activeProjects.length) return;
    this.editingExpenseId = expense?.id ?? '';
    this.expenseDraft = expense ? { ...expense } : this.emptyExpense();
    this.expenseDialog = true;
  }
  recalculate() {
    const e = this.expenseDraft;
    e.taxRate = Math.min(100, Math.max(0, Number(e.taxRate) || 0));
    e.subtotal = Number(e.quantity || 0) * Number(e.unitPrice || 0);
    e.tax = (e.subtotal * Number(e.taxRate || 0)) / 100;
    e.total = e.subtotal + e.tax;
  }
  setExpenseTaxRate(rate: number) {
    this.expenseDraft.taxRate = rate;
    this.recalculate();
  }
  async saveExpense() {
    this.recalculate();
    if (
      !this.expenseDraft.description.trim() ||
      !this.expenseDraft.projectId ||
      !this.expenseDraft.category.trim() ||
      this.expenseDraft.total < 0
    )
      return;
    const expense = {
      ...this.expenseDraft,
      id: this.editingExpenseId || crypto.randomUUID(),
    };
    await this.data.saveExpense(this.requireUid(), expense);
    this.expenseDialog = false;
  }
  async deleteExpense(expense: Expense) {
    if (confirm(`¿Eliminar “${expense.description}” por ${this.money(expense.total)}?`))
      await this.data.deleteExpense(this.requireUid(), expense.id);
  }
  editCategory(category?: Category) {
    this.editingCategoryId = category?.id ?? '';
    this.newCategory = category?.name ?? '';
  }
  async saveCategory() {
    const name = this.newCategory.trim();
    if (!name) return;
    await this.data.saveCategory(this.requireUid(), {
      id: this.editingCategoryId || crypto.randomUUID(),
      name,
    });
    this.editingCategoryId = '';
    this.newCategory = '';
  }
  async deleteCategory(category: Category) {
    if (
      !confirm(`¿Eliminar la categoría “${category.name}”? Los gastos anteriores la conservarán.`)
    )
      return;
    await this.data.deleteCategory(this.requireUid(), category.id);
  }
  async refreshCategories() {
    await this.data.refreshCategories(this.requireUid(), true);
  }
  openSupplier(supplier?: Supplier) {
    this.editingSupplierId = supplier?.id ?? '';
    this.supplierDraft = supplier ? { ...supplier } : this.emptySupplier();
    this.supplierDialog = true;
  }
  async saveSupplier() {
    if (!this.supplierDraft.name.trim()) return;
    await this.data.saveSupplier(this.requireUid(), {
      ...this.supplierDraft,
      id: this.editingSupplierId || crypto.randomUUID(),
      name: this.supplierDraft.name.trim(),
      contact: this.supplierDraft.contact.trim(),
      phone: this.supplierDraft.phone.trim(),
    });
    this.supplierDialog = false;
  }
  async deleteSupplier(supplier: Supplier) {
    if (confirm(`¿Eliminar al proveedor “${supplier.name}”?`))
      await this.data.deleteSupplier(this.requireUid(), supplier.id);
  }
  async saveVat() {
    this.vatRate = Math.min(100, Math.max(0, Number(this.vatRate) || 0));
    await this.data.saveVatRate(this.requireUid(), this.vatRate);
  }

  openWorker(worker?: Worker) {
    this.editingWorkerId = worker?.id ?? '';
    this.workerDraft = worker ? { ...worker, projectIds: [...worker.projectIds] } : this.emptyWorker();
    this.workerDialog = true;
  }
  async saveWorker() {
    if (!this.workerDraft.fullName.trim() || this.workerDraft.defaultRate < 0) return;
    const previous = this.workers.find((item) => item.id === this.editingWorkerId);
    const worker = { ...this.workerDraft, id: this.editingWorkerId || crypto.randomUUID(), fullName: this.workerDraft.fullName.trim() };
    await this.data.saveWorker(this.requireUid(), worker);
    if (!previous || previous.defaultRate !== worker.defaultRate) {
      const today = this.todayLocal();
      const prior = this.workerRates.filter((rate) => rate.workerId === worker.id && !rate.validTo);
      for (const rate of prior) await this.data.saveWorkerRate(this.requireUid(), { ...rate, validTo: today });
      const rate: WorkerRate = { id: crypto.randomUUID(), workerId: worker.id, projectId: '', dailyRate: worker.defaultRate, validFrom: today, validTo: '' };
      await this.data.saveWorkerRate(this.requireUid(), rate);
    }
    this.workerDialog = false;
  }
  async toggleWorker(worker: Worker) {
    if (!confirm(`¿${worker.status === 'ACTIVE' ? 'Desactivar' : 'Reactivar'} a ${worker.fullName}?`)) return;
    await this.data.saveWorker(this.requireUid(), { ...worker, status: worker.status === 'ACTIVE' ? 'INACTIVE' : 'ACTIVE' });
  }
  async addWorkerRole() { const name=this.newWorkerRole.trim(); if(!name)return; await this.data.saveWorkerRole(this.requireUid(),{id:crypto.randomUUID(),name,active:true}); this.newWorkerRole=''; }
  openAttendance(worker?: Worker) {
    this.attendanceDraft = this.emptyAttendance();
    if (worker) { this.attendanceDraft.workerId = worker.id; this.attendanceDraft.appliedRate = worker.defaultRate; }
    this.recalculateAttendance();
    this.attendanceDialog = true;
  }
  attendanceWorkerChanged() {
    const worker = this.workers.find((item) => item.id === this.attendanceDraft.workerId);
    const specific = this.workerRates.filter((rate) => rate.workerId === worker?.id && (!rate.projectId || rate.projectId === this.attendanceDraft.projectId) && rate.validFrom <= this.attendanceDraft.date && (!rate.validTo || rate.validTo >= this.attendanceDraft.date)).at(-1);
    this.attendanceDraft.appliedRate = specific?.dailyRate ?? worker?.defaultRate ?? 0;
    this.recalculateAttendance();
  }
  recalculateAttendance() { this.attendanceDraft.earned = calculateEarned(this.attendanceDraft.appliedRate, this.attendanceDraft.status, this.attendanceDraft.allocation); }
  async saveAttendance() {
    const item = this.attendanceDraft;
    if (!item.workerId || !item.projectId || !item.date) return;
    const existing = this.attendance.find((row) => row.workerId === item.workerId && row.projectId === item.projectId && row.date === item.date);
    const allocatedElsewhere = this.attendance.filter((row) => row.workerId === item.workerId && row.date === item.date && row.projectId !== item.projectId).reduce((sum,row)=>sum+row.allocation,0);
    if (allocatedElsewhere + item.allocation > 1.000001) { alert('La jornada ya está distribuida completamente entre otros proyectos.'); return; }
    await this.data.saveAttendance(this.requireUid(), { ...item, id: existing?.id ?? '', revision: (existing?.revision ?? 0) + 1, earned: calculateEarned(item.appliedRate, item.status, item.allocation) });
    this.attendanceDialog = false;
  }
  openAdvance(worker?: Worker) { this.advanceDraft = this.emptyAdvance(); if (worker) this.advanceDraft.workerId = worker.id; this.advanceDialog = true; }
  async saveAdvance() { if (!this.advanceDraft.workerId || this.advanceDraft.amount <= 0) return; await this.data.saveAdvance(this.requireUid(), { ...this.advanceDraft, id: this.advanceDraft.id || crypto.randomUUID() }); this.advanceDialog = false; }
  openPayment(worker?: Worker) { this.paymentDraft = this.emptyPayment(); if (worker) this.paymentDraft.workerId = worker.id; this.paymentDialog = true; }
  async savePayment() {
    if (!this.paymentDraft.workerId || this.paymentDraft.amount <= 0) return;
    if (this.paymentDraft.reference && this.workerPayments.some((item) => item.reference === this.paymentDraft.reference && item.workerId === this.paymentDraft.workerId)) { alert('Esta referencia de pago ya fue registrada para el trabajador.'); return; }
    await this.data.saveWorkerPayment(this.requireUid(), { ...this.paymentDraft, id: this.paymentDraft.id || crypto.randomUUID() }); this.paymentDialog = false;
  }

  async exportExcel() {
    const XLSX = await import('xlsx');
    const summary = this.activeProjects.map((p) => ({
      Proyecto: p.name,
      Estado: this.statusLabel(p.status),
      Presupuesto: p.budget,
      Gastado: this.monthlyExpenses
        .filter((e) => e.projectId === p.id)
        .reduce((s, e) => s + e.total, 0),
      Disponible:
        p.budget -
        this.monthlyExpenses.filter((e) => e.projectId === p.id).reduce((s, e) => s + e.total, 0),
      IVA: this.monthlyExpenses.filter((e) => e.projectId === p.id).reduce((s, e) => s + e.tax, 0),
      Movimientos: this.monthlyExpenses.filter((e) => e.projectId === p.id).length,
    }));
    const detail = this.monthlyExpenses.map((e) => ({
      Fecha: e.date,
      Factura: e.invoiceNumber,
      Proyecto: this.projectName(e.projectId),
      Categoría: e.category,
      Descripción: e.description,
      Proveedor: e.provider,
      Subtotal: e.subtotal,
      'IVA %': e.taxRate,
      IVA: e.tax,
      Total: e.total,
    }));
    const book = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(book, XLSX.utils.json_to_sheet(summary), 'Resumen por proyecto');
    XLSX.utils.book_append_sheet(
      book,
      XLSX.utils.json_to_sheet(this.monthlyCategorySummary),
      'Resumen por categoría',
    );
    XLSX.utils.book_append_sheet(book, XLSX.utils.json_to_sheet(detail), 'Detalle de compras');
    XLSX.writeFile(book, `Reporte_ObraFlow_${this.reportStart}_${this.reportEnd}.xlsx`);
  }
  async exportPdf() {
    const [{ default: jsPDF }, { default: autoTable }] = await Promise.all([
      import('jspdf'),
      import('jspdf-autotable'),
    ]);
    const doc = new jsPDF();
    doc.setFontSize(20);
    doc.setTextColor(23, 107, 86);
    doc.text('OBRAFLOW', 14, 18);
    doc.setFontSize(11);
    doc.setTextColor(80);
    doc.text(`Reporte del ${this.reportStart} al ${this.reportEnd}`, 14, 26);
    autoTable(doc, {
      startY: 32,
      head: [['Proyecto', 'Presupuesto', 'Gastado', 'Disponible', 'IVA']],
      body: this.activeProjects.map((p) => [
        p.name,
        this.money(p.budget),
        this.money(this.projectSpent(p.id)),
        this.money(p.budget - this.projectSpent(p.id)),
        this.money(
          this.monthlyExpenses.filter((e) => e.projectId === p.id).reduce((s, e) => s + e.tax, 0),
        ),
      ]),
      headStyles: { fillColor: [23, 107, 86] },
    });
    autoTable(doc, {
      startY: (doc as any).lastAutoTable.finalY + 12,
      head: [['Fecha', 'Factura', 'Proyecto', 'Artículo', 'Cant.', 'Subtotal', 'IVA', 'Total']],
      body: this.monthlyExpenses.map((e) => [
        e.date,
        e.invoiceNumber,
        this.projectName(e.projectId),
        e.description,
        e.quantity,
        this.money(e.subtotal),
        `${e.taxRate}% ${this.money(e.tax)}`,
        this.money(e.total),
      ]),
      headStyles: { fillColor: [23, 107, 86] },
    });
    doc.save(`Reporte_ObraFlow_${this.reportStart}_${this.reportEnd}.pdf`);
  }
  async exportLaborExcel() {
    const XLSX = await import('xlsx');
    const rows = this.laborByWorker.map(({ worker, summary }) => ({
      Trabajador: worker.fullName, Oficio: this.roleName(worker.roleId),
      'Días completos': summary.fullDays, 'Medios días': summary.halfDays,
      'Días equivalentes': summary.equivalentDays, Ganado: summary.earned,
      Anticipos: summary.advances, Pagos: summary.payments, Pendiente: summary.pending,
    }));
    const book = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(book, XLSX.utils.json_to_sheet(rows), 'Jornales');
    XLSX.utils.book_append_sheet(book, XLSX.utils.json_to_sheet(this.periodAttendance.map((item) => ({ Fecha:item.date,Trabajador:this.workerName(item.workerId),Proyecto:this.projectName(item.projectId),Asistencia:item.status,Tarifa:item.appliedRate,Distribución:item.allocation,Ganado:item.earned }))), 'Asistencia');
    XLSX.writeFile(book, `Jornales_ObraFlow_${this.laborPeriodStart}_${this.laborPeriodEnd}.xlsx`);
  }
  async exportLaborPdf() {
    const [{ default: jsPDF }, { default: autoTable }] = await Promise.all([import('jspdf'), import('jspdf-autotable')]);
    const doc = new jsPDF(); doc.setFontSize(18); doc.setTextColor(23,107,86); doc.text('OBRAFLOW · JORNALES',14,18); doc.setFontSize(10); doc.setTextColor(70); doc.text(`Período ${this.laborPeriodStart} al ${this.laborPeriodEnd}`,14,25);
    autoTable(doc,{startY:31,head:[['Trabajador','Días eq.','Ganado','Anticipos','Pagos','Pendiente']],body:this.laborByWorker.map(({worker,summary})=>[worker.fullName,summary.equivalentDays,this.money(summary.earned),this.money(summary.advances),this.money(summary.payments),this.money(summary.pending)]),headStyles:{fillColor:[23,107,86]}});
    doc.save(`Jornales_ObraFlow_${this.laborPeriodStart}_${this.laborPeriodEnd}.pdf`);
  }

  private emptyProject(): Project {
    return { id: '', name: '', location: '', budget: 0, progress: 0, status: 'ACTIVE' };
  }
  private emptyExpense(): Expense {
    return {
      id: '',
      projectId: this.activeProjects?.[0]?.id ?? '',
      category: this.categories?.[0]?.name ?? '',
      description: '',
      provider: '',
      invoiceNumber: '',
      quantity: 1,
      unitPrice: 0,
      subtotal: 0,
      taxRate: this.vatRate ?? 15,
      tax: 0,
      total: 0,
      date: this.todayLocal(),
    };
  }
  private emptySupplier(): Supplier {
    return { id: '', name: '', contact: '', phone: '' };
  }
  private emptyWorker(): Worker { return { id: '', fullName: '', nationalId: '', phone: '', roleId: this.workerRoles[0]?.id ?? 'otros', defaultRate: 0, startDate: this.todayLocal(), status: 'ACTIVE', notes: '', projectIds: [] }; }
  private emptyAttendance(): WorkerAttendance { return { id: '', workerId: this.activeWorkers[0]?.id ?? '', projectId: this.activeProjects[0]?.id ?? '', date: this.todayLocal(), status: 'FULL', appliedRate: this.activeWorkers[0]?.defaultRate ?? 0, allocation: 1, earned: 0, notes: '', revision: 0 }; }
  private emptyAdvance(): WorkerAdvance { return { id: '', workerId: this.activeWorkers[0]?.id ?? '', projectId: '', date: this.todayLocal(), amount: 0, method: 'CASH', reference: '', notes: '', appliedAmount: 0 }; }
  private emptyPayment(): WorkerPayment { return { id: '', workerId: this.activeWorkers[0]?.id ?? '', projectId: '', periodStart: this.startOfWeek(), periodEnd: this.endOfWeek(), date: this.todayLocal(), amount: 0, method: 'CASH', reference: '', notes: '' }; }
  private startOfWeek() { const d = new Date(); const day = (d.getDay() + 6) % 7; d.setDate(d.getDate() - day); return this.dateLocal(d); }
  private endOfWeek() { const d = new Date(); const day = (d.getDay() + 6) % 7; d.setDate(d.getDate() - day + 6); return this.dateLocal(d); }
  private dateLocal(value: Date) { const offset = value.getTimezoneOffset() * 60000; return new Date(value.getTime() - offset).toISOString().slice(0, 10); }
  private todayLocal() {
    const now = new Date();
    const offset = now.getTimezoneOffset() * 60000;
    return new Date(now.getTime() - offset).toISOString().slice(0, 10);
  }
  private oneMonthBefore(value: string) {
    const [year, month, day] = value.split('-').map(Number);
    const targetMonth = month === 1 ? 12 : month - 1;
    const targetYear = month === 1 ? year - 1 : year;
    const lastDay = new Date(targetYear, targetMonth, 0).getDate();
    return `${targetYear}-${String(targetMonth).padStart(2, '0')}-${String(Math.min(day, lastDay)).padStart(2, '0')}`;
  }
  private async connectUserData(uid: string, email: string | null) {
    this.activeDataUid = uid;
    const localOwner = localStorage.getItem('obraflow-local-owner');
    const seed =
      !localOwner || localOwner === uid
        ? this.legacySeed
        : {
            projects: structuredClone(PROJECTS),
            expenses: structuredClone(EXPENSES),
            categories: structuredClone(CATEGORIES),
            suppliers: structuredClone(SUPPLIERS),
            vatRate: 15,
          };
    try {
      await this.data.connect(uid, email, seed, {
        projects: (items) => (this.projects = items),
        expenses: (items) => (this.expenses = items),
        categories: (items) => (this.categories = items),
        suppliers: (items) => (this.suppliers = items),
        vatRate: (value) => (this.vatRate = value),
        workers: (items) => (this.workers = items),
        workerRoles: (items) => (this.workerRoles = items.length ? items : structuredClone(DEFAULT_ROLES)),
        workerRates: (items) => (this.workerRates = items),
        attendance: (items) => (this.attendance = items),
        advances: (items) => (this.advances = items),
        payments: (items) => (this.workerPayments = items),
      });
      if (!localOwner) localStorage.setItem('obraflow-local-owner', uid);
    } catch {
      this.activeDataUid = '';
    }
  }
  private requireUid() {
    const uid = this.auth.user()?.uid;
    if (!uid) throw new Error('No hay una sesión autenticada.');
    return uid;
  }
  private validateCredentials() {
    this.authError = '';
    if (!this.loginEmail.includes('@')) {
      this.authError = 'Ingresa un correo electrónico válido.';
      return false;
    }
    if (this.loginPassword.length < 6) {
      this.authError = 'La contraseña debe tener al menos 6 caracteres.';
      return false;
    }
    return true;
  }
  private async runAuth(action: () => Promise<unknown>) {
    this.authError = '';
    this.authLoading = true;
    try {
      await action();
    } catch (error) {
      const code = (error as { code?: string }).code ?? '';
      this.authError = this.authErrorMessage(code);
    } finally {
      this.authLoading = false;
    }
  }
  private authErrorMessage(code: string) {
    if (code.includes('email-already-in-use'))
      return 'Este correo ya tiene una cuenta. Pulsa Ingresar.';
    if (code.includes('invalid-credential') || code.includes('wrong-password'))
      return 'Correo o contraseña incorrectos.';
    if (code.includes('popup-closed')) return 'Se cerró la ventana de Google antes de terminar.';
    if (code.includes('unauthorized-domain'))
      return 'Este dominio todavía no está autorizado en Firebase Authentication.';
    if (code.includes('operation-not-allowed'))
      return 'Activa este método de acceso en Firebase Authentication.';
    if (code.includes('network-request-failed'))
      return 'No se pudo conectar con Firebase. Revisa tu conexión.';
    return 'No se pudo completar el acceso. Inténtalo nuevamente.';
  }
  private load<T>(key: string, fallback: T): T {
    try {
      return JSON.parse(localStorage.getItem(key) ?? '') as T;
    } catch {
      return structuredClone(fallback);
    }
  }
}
