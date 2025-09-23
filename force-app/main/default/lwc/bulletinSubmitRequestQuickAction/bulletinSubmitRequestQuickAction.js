import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

import listActiveCategories from '@salesforce/apex/BulletinService.listActiveCategories';
import createRequest from '@salesforce/apex/BulletinService.createRequest';

export default class BulletinSubmitRequestQuickAction extends LightningElement {
  @track type = 'Suggestion';
  @track title = '';
  @track bodyHtml = this.defaultBody;

  @track categoryOptions = [];
  @track selectedCategoryIds = [];
  @track pendingTag = null;

  submitting = false;
  labelsById = {};

  get typeOptions() {
    return [
      { label: 'Suggestion', value: 'Suggestion' },
      { label: 'Support Request', value: 'Support Request' }
    ];
  }

  get selectedCategoryPills() {
    return (this.selectedCategoryIds || []).map(v => ({ value: v, label: this.labelsById[v] || v }));
  }

  get disableSubmit() {
    return (
      this.submitting ||
      !this.hasContent(this.bodyHtml) ||
      (this.selectedCategoryIds || []).length === 0
    );
  }

  get defaultBody() {
    return [
      '<div>',
      '<h3><strong>Description</strong></h3>',
      '<p><em>What outcome are you chasing? What’s the ask?</em></p>',
      '<h3><strong>Rationale / Context</strong></h3>',
      '<p><em>Why does this matter? Any deadlines or impact?</em></p>',
      '<h3><strong>Additional Notes</strong></h3>',
      '<p><em>Anything else we should know?</em></p>',
      '</div>'
    ].join('');
  }

  connectedCallback() { this.loadCategories(); }

  async loadCategories() {
    try {
      const rows = await listActiveCategories(); // [{id, name}]
      this.categoryOptions = (rows || []).map(r => ({ label: r.name, value: r.id }));
      this.labelsById = {};
      (rows || []).forEach(r => (this.labelsById[r.id] = r.name));
    } catch (e) {
      this.toast('Error loading categories', e?.body?.message || e?.message, 'error');
    }
  }

  onType(e) { this.type = e.detail.value; }
  onTitle(e) { this.title = e.detail.value; }
  onBody(e) { this.bodyHtml = e.detail.value; }

  handlePickTag(e) {
    const id = e.detail.value;
    if (!id) return;
    if (!this.selectedCategoryIds.includes(id)) {
      this.selectedCategoryIds = [...this.selectedCategoryIds, id];
    }
    this.pendingTag = null;
  }

  removeTag(evt) {
    const id = evt.target.name;
    this.selectedCategoryIds = (this.selectedCategoryIds || []).filter(v => v !== id);
  }

  hasContent(html) {
    const text = (html || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
    return text.length > 0;
  }

  async handleSubmit() {
    if (this.disableSubmit) return;
    this.submitting = true;
    try {
      await createRequest({
        type: this.type,
        title: this.title,
        bodyHtml: this.bodyHtml,
        categoryIds: this.selectedCategoryIds
      });
      this.toast('Request submitted', 'Thanks! We’ll take a look.', 'success');

      // Close both ways:
      this.dispatchEvent(new CustomEvent('close'));          // Aura wrapper listens and fires force:closeQuickAction
      this.dispatchEvent(new CloseActionScreenEvent());      // closes when used as LWC ScreenAction
    } catch (e) {
      this.toast('Submit failed', e?.body?.message || e?.message, 'error');
    } finally {
      this.submitting = false;
    }
  }

  handleCancel() {
    // Close both ways:
    this.dispatchEvent(new CustomEvent('close'));
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
