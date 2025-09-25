import { LightningElement, api, track } from 'lwc';

export default class SuggestionBox extends LightningElement {
  @api records = [];
  @api loading = false;
  @api categories = [];
  @api users = [];   // [{id,name}]
  @api isAdmin = false;

  // Parent-driven owner scope (e.g., 'ANY' for admins on load, 'ME' for users)
  _ownerScope = 'ME';
  @api
  get ownerScope() { return this._ownerScope; }
  set ownerScope(val) {
    // Only update if different to avoid redundant querychange loops
    const next = val || (this.isAdmin ? 'ANY' : 'ME');
    if (next !== this._ownerScope) this._ownerScope = next;
  }

  @track search = '';
  @track status = '';
  @track category = '';

  connectedCallback(){
    // Safety default; parent will set ownerScope shortly after mount
    if(this.isAdmin) this._ownerScope = 'ANY';
  }

  get decisionOptions(){
    return [
      { label:'Any', value:'' },
      { label:'Under Review', value:'Under Review' },
      { label:'Accepted', value:'Accepted' },
      { label:'Rejected', value:'Rejected' },
      { label:'Implemented', value:'Implemented' }
    ];
  }
  get categoryOptions(){
    const base = [{ label:'All', value:'' }];
    return base.concat(this.categories || []);
  }
  get ownerOptions(){
    // Suggestions filter by Submitter (CreatedBy)
    const base = [
      { label:'Any', value:'ANY' },
      { label:'Me', value:'ME' }
    ];
    const others = (this.users || []).map(u => ({ label:u.name, value:`USER:${u.id}` }));
    return base.concat(others);
  }

  notify(){
    this.dispatchEvent(new CustomEvent('querychange', {
      detail: {
        search:this.search,
        status:this.status,
        category:this.category,
        ownerScope:this._ownerScope
      }
    }));
  }

  onSearch(e){ this.search = e.target.value; this.notify(); }
  onDecision(e){ this.status = e.detail.value; this.notify(); }
  onCategory(e){ this.category = e.detail.value; this.notify(); }
  onOwner(e){ this._ownerScope = e.detail.value; this.notify(); }

  // Table
  get columns(){
    return [
      { label:'#', fieldName:'number', initialWidth:80 },
      { label:'Title', fieldName:'title' },
      { label:'Decision', fieldName:'status' },
      { label:'Category', fieldName:'categoryText' },
      { label:'Submitter', fieldName:'createdByName' },
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

  newSuggestion(){ this.dispatchEvent(new CustomEvent('newsuggestion')); }
}
