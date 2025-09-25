import { LightningElement, api, track } from 'lwc';
import listActiveStatusOptions from '@salesforce/apex/BulletinService.listActiveStatusOptions';

export default class SuggestionBox extends LightningElement {
  @api records = [];
  @api loading = false;
  @api categories = [];
  @api users = [];
  @api isAdmin = false;

  // Owner scope (public)
  _ownerScope = 'ME';
  @api
  get ownerScope() { return this._ownerScope; }
  set ownerScope(val) {
    const next = val || (this.isAdmin ? 'ANY' : 'ME');
    this._ownerScope = next;
  }

  // Presets / state
  @track search = '';
  @track status = '';
  @track category = '';

  @api
  get presetStatus() { return this.status; }
  set presetStatus(v) { this.status = v || ''; }

  @api
  get presetCategory() { return this.category; }
  set presetCategory(v) { this.category = v || ''; }

  @api
  get presetSearch() { return this.search; }
  set presetSearch(v) { this.search = v || ''; }

  @track decisionOptions = [{ label: 'Any', value: '' }];

  connectedCallback(){
    if(this.isAdmin) this._ownerScope = this._ownerScope || 'ANY';
    this.loadDecisionOptions();
  }

  async loadDecisionOptions(){
    try {
      const rows = await listActiveStatusOptions({ type: 'Suggestion' });
      const opts = (rows || []).map(r => ({ label: r.name, value: r.id }));
      this.decisionOptions = [{ label: 'Any', value: '' }, ...opts];
    } catch(_e) {
      this.decisionOptions = [{ label: 'Any', value: '' }];
    }
  }

  get categoryOptions(){
    const base = [{ label:'All', value:'' }];
    return base.concat(this.categories || []);
  }

  get ownerOptions(){
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

  // Inputs
  onSearch(e){ this.search = e.target.value; this.notify(); }
  onDecision(e){ this.status = e.detail.value; this.notify(); }
  onCategory(e){ this.category = e.detail.value; this.notify(); }
  onOwner(e){ this._ownerScope = e.detail.value; this.notify(); }

  // Reset to defaults
  resetFilters(){
    this.search = '';
    this.status = '';
    this.category = '';
    this._ownerScope = this.isAdmin ? 'ANY' : 'ME';
    this.notify();
  }

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
