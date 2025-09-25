import { LightningElement, track } from 'lwc';
import listSuggestions from '@salesforce/apex/BulletinService.listSuggestions';
import listSupportTickets from '@salesforce/apex/BulletinService.listSupportTickets';
import getRequest from '@salesforce/apex/BulletinService.getRequest';
import updateStatus from '@salesforce/apex/BulletinService.updateStatus';
import listComments from '@salesforce/apex/BulletinService.listComments';
import createComment from '@salesforce/apex/BulletinService.createComment';
import getBulletinContext from '@salesforce/apex/BulletinService.getBulletinContext';
import listActiveCategoryNames from '@salesforce/apex/BulletinService.listActiveCategoryNames';

const SUG_KEY = 'bb_filters_suggestion';
const SUP_KEY = 'bb_filters_support';

export default class BulletinBoard extends LightningElement {
  @track isSuggestions = true;
  @track isSupport = false;

  @track loadingSuggestions = false;
  @track loadingSupport = false;

  @track suggestions = [];
  @track tickets = [];

  @track categoryOptions = [];

  // context
  @track isAdmin = false;
  @track adminUsers = [];
  @track bulletinUsers = [];

  // detail modal
  @track detailOpen = false;
  @track activeRecord = null;
  @track activeComments = [];
  @track statusSaved = false;

  // submit modal
  @track flowOpen = false;
  @track flowTitle = 'New Request';
  @track initialType = 'Suggestion';

  // last filters (persisted per tab)
  lastSuggestionFilters = { pageSize: 50, ownerScope: 'ME', search: '', status: '', categoryName: '' };
  lastSupportFilters    = { pageSize: 50, ownerScope: 'ANY', search: '', status: '', categoryName: '' };

  async connectedCallback() {
    try {
      const ctx = await getBulletinContext();
      this.isAdmin = !!ctx?.isAdmin;
      this.adminUsers = ctx?.adminUsers || [];
      this.bulletinUsers = ctx?.bulletinUsers || [];

      // Defaults depend on role
      this.lastSuggestionFilters.ownerScope = this.isAdmin ? 'ANY' : 'ME';
      this.lastSupportFilters.ownerScope    = this.isAdmin ? 'ANY' : 'ANY';

      // Restore persisted filters (if present)
      this.restoreFilters();

      const cats = await listActiveCategoryNames();
      this.categoryOptions = (cats || []).map(n => ({ label: n, value: n }));
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error(e);
    }

    // Initial fetch for the default tab
    this.refreshSuggestions(this.lastSuggestionFilters);
  }

  restoreFilters(){
    try {
      const rawSug = window.localStorage.getItem(SUG_KEY);
      if (rawSug) {
        const f = JSON.parse(rawSug);
        this.lastSuggestionFilters = { ...this.lastSuggestionFilters, ...f, pageSize: 50 };
      }
    } catch(_) {}
    try {
      const rawSup = window.localStorage.getItem(SUP_KEY);
      if (rawSup) {
        const f = JSON.parse(rawSup);
        this.lastSupportFilters = { ...this.lastSupportFilters, ...f, pageSize: 50 };
      }
    } catch(_) {}
  }
  persistFilters(){
    try { window.localStorage.setItem(SUG_KEY, JSON.stringify(this.lastSuggestionFilters)); } catch(_) {}
    try { window.localStorage.setItem(SUP_KEY, JSON.stringify(this.lastSupportFilters)); } catch(_) {}
  }

  // Tabs
  get suggestionTabClass(){ return `tab ${this.isSuggestions?'active':''}`; }
  get supportTabClass(){ return `tab ${this.isSupport?'active':''}`; }
  showSuggestions = () => {
    this.isSuggestions = true; this.isSupport = false;
    this.refreshSuggestions(this.lastSuggestionFilters);
  }
  showSupport     = () => {
    this.isSuggestions = false; this.isSupport = true;
    this.refreshSupport(this.lastSupportFilters);
  }

  // Fetchers
  async refreshSuggestions(filters = {}) {
    this.loadingSuggestions = true;
    try {
      const res = await listSuggestions({ filtersJson: JSON.stringify(filters) });
      this.suggestions = (res || []).map(r => ({
        ...r,
        number: r.recordNumber,
        categoryText: (r.categories || []).join(', ')
      }));
    } catch (e) { console.error(e); }
    this.loadingSuggestions = false;
  }

  async refreshSupport(filters = {}) {
    this.loadingSupport = true;
    try {
      const res = await listSupportTickets({ filtersJson: JSON.stringify(filters) });
      this.tickets = (res || []).map(r => ({
        ...r,
        number: r.recordNumber,
        categoryText: (r.categories || []).join(', ')
      }));
    } catch (e) { console.error(e); }
    this.loadingSupport = false;
  }

  // Child filter events
  onSuggestionsQuery(e){
    const f = e.detail || {};
    this.lastSuggestionFilters = {
      search: f.search || '',
      status: f.status || '',
      categoryName: f.category || '',
      ownerScope: f.ownerScope || (this.isAdmin ? 'ANY' : 'ME'),
      pageSize: 50
    };
    this.persistFilters();
    this.refreshSuggestions(this.lastSuggestionFilters);
  }

  onSupportQuery(e){
    const f = e.detail || {};
    this.lastSupportFilters = {
      search: f.search || '',
      status: f.status || '',
      categoryName: f.category || '',
      ownerScope: this.isAdmin ? (f.ownerScope || 'ANY') : 'ANY',
      pageSize: 50
    };
    this.persistFilters();
    this.refreshSupport(this.lastSupportFilters);
  }

  // Detail modal
  async openDetail(e){
    const id = e?.detail?.id || e;
    try{
      const rec = await getRequest({ id });
      const cmts = await listComments({ requestId: id });
      this.activeRecord = rec;
      this.activeComments = cmts || [];
      this.detailOpen = true;
    }catch(err){ console.error(err); }
  }
  closeDetail(){ this.detailOpen=false; this.activeRecord=null; this.activeComments=[]; }

  async handleSaveStatus(e){
    const { id, status } = e.detail || {};
    try{
      const rec = await updateStatus({ id, status });
      this.activeRecord = rec;
      this.statusSaved = true;
      setTimeout(()=>{ this.statusSaved=false; },1600);
      if(this.isSuggestions) this.refreshSuggestions(this.lastSuggestionFilters);
      else this.refreshSupport(this.lastSupportFilters);
    }catch(err){ console.error(err); }
  }

  async handlePostComment(e){
    const { id, body } = e.detail || {};
    try{
      const newComment = await createComment({ requestId: id, body });
      this.activeComments = [ ...(this.activeComments || []), newComment ];
    }catch(err){ console.error(err); }
  }

  // Submit LWC launcher
  launchNewSuggestion(){
    this.flowTitle = 'New Suggestion';
    this.initialType = 'Suggestion';
    this.flowOpen = true;
  }
  launchNewTicket(){
    this.flowTitle = 'New Support Request';
    this.initialType = 'Support Request';
    this.flowOpen = true;
  }

  // Child submit events
  handleSubmitSuccess(){
    this.flowOpen = false;
    if(this.isSuggestions) this.refreshSuggestions(this.lastSuggestionFilters);
    if(this.isSupport)     this.refreshSupport(this.lastSupportFilters);
  }

  // Modal helpers
  closeFlow(){ this.flowOpen=false; }
  closeFlowIfBackdrop(e){ if(e.target.classList.contains('bb-backdrop')) this.closeFlow(); }
  stop(e){ e.stopPropagation(); }
}
