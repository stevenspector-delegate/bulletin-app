import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listActiveCategories from '@salesforce/apex/BulletinService.listActiveCategories';
import createRequest from '@salesforce/apex/BulletinService.createRequest';

const DEFAULT_TEMPLATE = `
  <h4 style="margin:0 0 6px 0;color:#16325C;font-weight:600;">Description</h4>
  <ul><li><em>Briefly describe the outcome you want and the concrete details.</em></li></ul>

  <h4 style="margin:12px 0 6px 0;color:#16325C;font-weight:600;">Rationale / Context</h4>
  <ul><li><em>Why this matters, who’s impacted, any time sensitivity.</em></li></ul>

  <h4 style="margin:12px 0 6px 0;color:#16325C;font-weight:600;">Additional Notes</h4>
  <ul><li><em>Steps tried, examples, links, screenshots, etc.</em></li></ul>
`.trim();

export default class BulletinSubmitRequest extends LightningElement {
  @api initialType;
  @track type = 'Suggestion';
  @track title = '';
  @track bodyHtml = '';
  @track selectedCategoryIds = [];
  @track categoryOptions = [];
  @track saving = false;

  typeOptions = [
    { label: 'Suggestion', value: 'Suggestion' },
    { label: 'Support Request', value: 'Support Request' }
  ];
  formats = ['bold','italic','underline','strike','list','link','image','code','header','color','background','align','clean'];

  connectedCallback(){
    if (this.initialType && (this.initialType === 'Suggestion' || this.initialType === 'Support Request')) {
      this.type = this.initialType;
    }
    this.loadCategories();
    this.bodyHtml = DEFAULT_TEMPLATE;
  }

  async loadCategories(){
    try{
      const res = await listActiveCategories();
      this.categoryOptions = (res || []).map(r => ({ label: r.name, value: r.id }));
    }catch(e){
      this.toast('Error loading categories', e?.body?.message || e?.message || 'Unknown error', 'error');
    }
  }

  get effectiveTitle(){
    if (this.title && this.title.trim()) return this.title.trim();
    const text = (this.bodyHtml || '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
    if(!text) return '(will default to "New request")';
    return text.length > 28 ? text.slice(0,25) + '...' : text;
  }

  onTypeChange(e){ this.type = e.detail.value; }
  onTitleChange(e){ this.title = e.detail.value || ''; }
  onCategoriesChange(e){ this.selectedCategoryIds = e.detail.value || []; }
  onBodyChange(e){ this.bodyHtml = e.detail.value || ''; }

  async submit(){
    if(!this.type){
      this.toast('Type required', 'Please choose Suggestion or Support Request.', 'warning'); return;
    }
    if(!this.selectedCategoryIds?.length){
      this.toast('Pick at least one tag', 'Select one or more categories.', 'warning'); return;
    }
    const stripped = (this.bodyHtml || '').replace(/<[^>]*>/g,'').trim();
    if(!stripped){
      this.toast('Description required', 'Please describe your request.', 'warning'); return;
    }

    this.saving = true;
    try{
      const rec = await createRequest({
        type: this.type,
        title: (this.title || '').trim(),
        bodyHtml: this.bodyHtml,
        categoryIds: this.selectedCategoryIds
      });
      this.toast('Request submitted', `${rec?.recordNumber || ''} created`, 'success');
      this.dispatchEvent(new CustomEvent('success', { detail: { id: rec?.id }, bubbles: true, composed: true }));
      // Reset if used standalone
      this.type = this.initialType || 'Suggestion';
      this.title = '';
      this.bodyHtml = DEFAULT_TEMPLATE;
      this.selectedCategoryIds = [];
    }catch(e){
      this.toast('Submit failed', e?.body?.message || e?.message || 'Unknown error', 'error');
    }finally{
      this.saving = false;
    }
  }

cancel() {
  this.dispatchEvent(new CustomEvent('cancel', { bubbles: true, composed: true }));
}  

toast(title, message, variant){ this.dispatchEvent(new ShowToastEvent({ title, message, variant })); }

}
