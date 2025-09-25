import { LightningElement, api, track } from 'lwc';
import listActiveStatusOptions from '@salesforce/apex/BulletinService.listActiveStatusOptions';

export default class SupportConsole extends LightningElement {
  @api records = [];
  @api loading = false;
  @api categories = [];
  @api isAdmin = false;
  @api admins = [];

  @track search=''; @track status=''; @track category='';
  @track ownerScope='ANY';
  @track view='table';

  @api
  get presetStatus() { return this.status; }
  set presetStatus(v) { this.status = v || ''; }

  @api
  get presetCategory() { return this.category; }
  set presetCategory(v) { this.category = v || ''; }

  @api
  get presetSearch() { return this.search; }
  set presetSearch(v) { this.search = v || ''; }

  @api
  get presetOwnerScope() { return this.ownerScope; }
  set presetOwnerScope(v) { this.ownerScope = v || 'ANY'; }

  @track statusOptions = [{ label:'Any', value:'' }];

  connectedCallback(){
    this.loadStatusOptions();
  }

  async loadStatusOptions(){
    try {
      const rows = await listActiveStatusOptions({ type: 'Support Request' });
      const opts = (rows || []).map(r => ({ label: r.name, value: r.id }));
      this.statusOptions = [{ label:'Any', value:'' }, ...opts];
    } catch(_e) {
      this.statusOptions = [{ label:'Any', value:'' }];
    }
  }

  get categoryOptions(){
    const base = [{ label:'All', value:'' }];
    return base.concat(this.categories || []);
  }

  get ownerOptions(){
    if(!this.isAdmin) return [];
    const base = [
      { label:'Any', value:'ANY' },
      { label:'Me', value:'ME' },
      { label:'Unassigned', value:'UNASSIGNED' }
    ];
    const others = (this.admins || []).map(u => ({ label:u.name, value:`USER:${u.id}` }));
    return base.concat(others);
  }

  get showingTable(){ return this.view==='table'; }
  get showingKanban(){ return this.view==='kanban'; }
  get tableVariant(){ return this.showingTable ? 'brand' : 'neutral'; }
  get kanbanVariant(){ return this.showingKanban ? 'brand' : 'neutral'; }

  notify(){
    this.dispatchEvent(new CustomEvent('querychange', {
      detail: { search:this.search, status:this.status, category:this.category, ownerScope: (this.isAdmin ? this.ownerScope : undefined) }
    }));
  }

  // Inputs
  onSearch(e){ this.search = e.target.value; this.notify(); }
  onStatus(e){ this.status = e.detail.value; this.notify(); }
  onCategory(e){ this.category = e.detail.value; this.notify(); }
  onOwner(e){ this.ownerScope = e.detail.value; this.notify(); }

  // Reset to defaults
  resetFilters(){
    this.search = '';
    this.status = '';
    this.category = '';
    this.ownerScope = 'ANY';
    this.notify();
  }

  showTable(){ this.view='table'; }
  showKanban(){ this.view='kanban'; }

  newTicket(){ this.dispatchEvent(new CustomEvent('newticket')); }

  // Table
  get columns(){
    return [
      { label:'#', fieldName:'number', initialWidth:80 },
      { label:'Title', fieldName:'title' },
      { label:'Priority', fieldName:'priority', initialWidth:110 },
      { label:'Status', fieldName:'status', initialWidth:140 },
      { label:'Category', fieldName:'categoryText' },
      { label:'Assignee', fieldName:'ownerName' },
      { label:'Comments', fieldName:'commentCount', type:'number', initialWidth:120, cellAttributes:{ alignment:'center' } },
      { label:'Updated', fieldName:'updatedDate', initialWidth:110 },
      { type:'button', typeAttributes: { label:'Open', name:'open', variant:'brand-outline' }, initialWidth:110 }
    ];
  }
  get rowsForTable(){ return this.records || []; }
  handleRowAction(e){
    const row = e.detail.row;
    this.dispatchEvent(new CustomEvent('openrecord', { detail:{ id: row.id }}));
  }

  // Kanban
  get columnsMap(){
    const dynamicCols = (this.statusOptions || []).filter(o => o.value !== '');
    if (!dynamicCols.length) {
      const cols = [
        { key:'new', label:'New', items:[] },
        { key:'inrev', label:'In Review', items:[] },
        { key:'prog', label:'In Progress', items:[] },
        { key:'done', label:'Done', items:[] },
        { key:'closed', label:'Closed', items:[] }
      ];
      const by = (status) => {
        if(!status) return cols[0];
        const s = status.toLowerCase();
        if(s==='new') return cols[0];
        if(s==='in review') return cols[1];
        if(s==='in progress') return cols[2];
        if(s==='done') return cols[3];
        if(s==='closed') return cols[4];
        return cols[0];
      };
      (this.records||[]).forEach(r => by(r.status).items.push(r));
      return cols;
    }

    const cols = dynamicCols.map((opt, idx) => ({
      key: `col_${idx}`,
      label: opt.label,
      items: []
    }));

    const indexByLabel = new Map(dynamicCols.map((o, i) => [o.label.toLowerCase(), i]));
    (this.records || []).forEach(r => {
      const i = indexByLabel.get((r.status || '').toLowerCase());
      const col = (i !== undefined) ? cols[i] : cols[0];
      col.items.push(r);
    });

    return cols;
  }

  openRecord(e){
    const id = e.currentTarget?.dataset?.id;
    if(id){ this.dispatchEvent(new CustomEvent('openrecord', { detail:{ id }})); }
  }
}
