import { LightningElement, api, track } from 'lwc';

export default class SupportConsole extends LightningElement {
  @api records = [];
  @api loading = false;
  @api categories = [];

  // Admin context passed from parent
  @api isAdmin = false;
  @api admins = []; // [{id,name}]

  @track search=''; @track status=''; @track category='';
  @track ownerScope='ANY';  // 'ANY' | 'ME' | 'UNASSIGNED' | 'USER:<Id>'
  @track view='table';

  get statusOptions(){
    return [
      { label:'Any', value:''},
      { label:'New', value:'New' },
      { label:'In Review', value:'In Review' },
      { label:'In Progress', value:'In Progress' },
      { label:'Done', value:'Done' },
      { label:'Closed', value:'Closed' }
    ];
  }
  get categoryOptions(){
    const base = [{ label:'All', value:'' }];
    return base.concat(this.categories || []);
  }

  // Build Owner picklist for admins
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

  // View
  get showingTable(){ return this.view==='table'; }
  get showingKanban(){ return this.view==='kanban'; }
  get tableVariant(){ return this.showingTable ? 'brand' : 'neutral'; }
  get kanbanVariant(){ return this.showingKanban ? 'brand' : 'neutral'; }

  notify(){
    this.dispatchEvent(new CustomEvent('querychange', {
      detail: { search:this.search, status:this.status, category:this.category, ownerScope: (this.isAdmin ? this.ownerScope : undefined) }
    }));
  }
  onSearch(e){ this.search = e.target.value; this.notify(); }
  onStatus(e){ this.status = e.detail.value; this.notify(); }
  onCategory(e){ this.category = e.detail.value; this.notify(); }
  onOwner(e){ this.ownerScope = e.detail.value; this.notify(); }

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

  openRecord(e){
    const id = e.currentTarget?.dataset?.id;
    if(id){ this.dispatchEvent(new CustomEvent('openrecord', { detail:{ id }})); }
  }
}
