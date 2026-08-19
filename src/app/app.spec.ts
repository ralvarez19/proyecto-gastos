import { TestBed } from '@angular/core/testing';
import { App } from './app';

describe('App', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [App],
    }).compileComponents();
  });

  it('should create the app', () => {
    const fixture = TestBed.createComponent(App);
    const app = fixture.componentInstance;
    expect(app).toBeTruthy();
  });

  it('should render title', async () => {
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const compiled = fixture.nativeElement as HTMLElement;
    expect(compiled.querySelector('h1')?.textContent).toContain('Bienvenido');
  });

  it('permite editar el IVA del gasto y recalcula el total', () => {
    const fixture = TestBed.createComponent(App);
    const app = fixture.componentInstance;
    app.expenseDraft.quantity = 2;
    app.expenseDraft.unitPrice = 100;

    app.setExpenseTaxRate(5);

    expect(app.expenseDraft.taxRate).toBe(5);
    expect(app.expenseDraft.subtotal).toBe(200);
    expect(app.expenseDraft.tax).toBe(10);
    expect(app.expenseDraft.total).toBe(210);
  });
});
