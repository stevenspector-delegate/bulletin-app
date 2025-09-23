import { LightningElement, track } from 'lwc';
import listSuggestions from '@salesforce/apex/BulletinService.listSuggestions';
import listSupportTickets from '@salesforce/apex/BulletinService.listSupportTickets';
import getRequest from '@salesforce/apex/BulletinService.getRequest';
import updateStatus from '@salesforce/apex/BulletinService.updateStatus';
import listComments from '@salesforce/apex/BulletinService.listComments';
import createComment from '@salesforce/apex/BulletinService.createComment';
import getBulletinContext from '@salesforce/apex/BulletinService.getBulletinContext';
import listActiveCategoryNames from '@salesforce/apex/BulletinService.listActiveCategoryNames';

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

  // flow modal
  @track flowOpen = false;
  @track flowApiName = 'Request_New_Request_Wizard';
  @track flowTitle = 'New Request';
  @track flowKey = 0; // force remount

  // last filters
  lastSuggestionFilters = { pageSize: 50, ownerScope: 'ME' };   // parent defaults: users=ME, admins=ANY
  lastSupportFilters    = { pageSize: 50, ownerScope: 'ANY' };

  async connectedCallback() {
    try {
      // Context (admins, bulletin users)
      const ctx = await getBulletinContext();
      this.isAdmin = !!ctx?.isAdmin;
      this.adminUsers = ctx?.adminUsers || [];
      this.bulletinUsers = ctx?.bulletinUsers || [];

      // Suggestion default scope depends on role
      this.lastSuggestionFilters.ownerScope = this.isAdmin ? 'ANY' : 'ME';

      // Load ALL active categories for dropdowns (stop deriving from rows)
      const cats = await listActiveCategoryNames();
      this.categoryOptions = (cats || []).map(n => ({ label: n, value: n }));
    } catch (e) {
      console.error(e);
    }

    // Initial data
    this.refreshSuggestions(this.lastSuggestionFilters);
  }

  // Tabs
  get suggestionTabClass(){ return `tab ${this.isSuggestions?'active':''}`; }
  get supportTabClass(){ return `tab ${this.isSupport?'active':''}`; }
  showSuggestions = () => { this.isSuggestions = true; this.isSupport = false; this.refreshSuggestions(this.lastSuggestionFilters); }
  showSupport     = () => { this.isSuggestions = false; this.isSupport = true; this.refreshSupport(this.lastSupportFilters); }

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
    } catch (e) {
      console.error(e);
    }
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
    } catch (e) {
      console.error(e);
    }
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

  // Flow launcher (force remount with key)
  launchNewSuggestion(){ this.flowTitle='New Suggestion'; this.flowApiName='Bulletin_Submit_a_Request'; this.flowKey = Date.now(); this.flowOpen=true; }
  launchNewTicket(){ this.flowTitle='New Support Request'; this.flowApiName='Bulletin_Submit_a_Request'; this.flowKey = Date.now(); this.flowOpen=true; }
  handleFlowStatus(evt){
    const s = evt.detail?.status;
    if(s==='FINISHED' || s==='FINISHED_SCREEN' || s==='PAUSED'){
      this.flowOpen=false;
      this.refreshSuggestions(this.lastSuggestionFilters);
      this.refreshSupport(this.lastSupportFilters);
    }
  }
  closeFlow(){ this.flowOpen=false; }
  closeFlowIfBackdrop(e){ if(e.target.classList.contains('bb-backdrop')) this.closeFlow(); }
  stop(e){ e.stopPropagation(); }
}
