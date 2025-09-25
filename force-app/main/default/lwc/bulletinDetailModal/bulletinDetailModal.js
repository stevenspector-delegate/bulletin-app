import { LightningElement, api, track } from 'lwc';
import userId from '@salesforce/user/Id';

import updateDescription from '@salesforce/apex/BulletinService.updateDescription';
import updateOwner from '@salesforce/apex/BulletinService.updateOwner';
import getSupportOwnerOptions from '@salesforce/apex/BulletinService.getSupportOwnerOptions';
import getBulletinContext from '@salesforce/apex/BulletinService.getBulletinContext';
import listActiveStatusOptions from '@salesforce/apex/BulletinService.listActiveStatusOptions';

export default class BulletinDetailModal extends LightningElement {
  @api open = false;

  // record (init on change)
  _record;
  @api
  set record(val){
    this._record = val || null;
    this._initForRecord();
  }
  get record(){ return this._record; }

  // role context
  @api statusSaved = false;
  @track isAdmin = false;

  // comments
  _comments = [];
  @track commentsView = [];
  @api
  set comments(value){
    this._comments = value || [];
    this.commentsView = this._comments.map(c => ({
      ...c,
      when: this._formatWhen(c.createdOn)
    }));
  }
  get comments(){ return this._comments; }

  // description editing
  @track editingDesc = false;
  @track editableHtml = '';
  @track descSaved = false;
  rteFormats = ['bold','italic','underline','strike','list','link','image','code','header','color','background','align','clean'];

  // state (status/decision)
  stateLabel = 'Status';
  @track stateOptions = [];       
  @track stateValue;            
  get disableSave(){
    return !this.isAdmin || !this.stateValue;
  }

  // owner 
  @track ownerOptions = [];
  @track ownerId;
  @track ownerSaved = false;
  _ownerOptsLoadedFor;

  // comment composer
  composer = '';

  connectedCallback(){
    getBulletinContext()
      .then(ctx => {
        this.isAdmin = !!ctx?.isAdmin;
        this._initForRecord();
      })
      .catch(() => { this.isAdmin = false; });
  }

  // UI getters
  get titleText(){
    return `${this.record?.recordNumber || ''} · ${this.record?.title || 'Record Detail'}`;
  }
  get commentCount(){ return (this.commentsView || []).length; }
  get canEditDescription(){
    if (!this.record) return false;
    return this.isAdmin || this.record.createdById === userId;
  }
  get showOwner(){
    return this.isAdmin && this.record && this.record.type === 'Support Request';
  }
  get showOwnerReadOnly(){
    return !this.isAdmin && this.record && this.record.type === 'Support Request' && this.record.ownerName;
  }
  get categoriesText(){
    const arr = this.record?.categories || [];
    return Array.isArray(arr) ? arr.join(', ') : '';
  }

  // init per record
  async _initForRecord(){
    if (!this.record) return;

    this.editingDesc = false;
    this.descSaved = false;
    this.ownerSaved = false;

    // Label per type
    this.stateLabel = (this.record.type === 'Support Request') ? 'Status' : 'Decision';

    try {
      const rows = await listActiveStatusOptions({ type: this.record.type });
      this.stateOptions = (rows || []).map(r => ({ label: r.name, value: r.id }));
      const match = this.stateOptions.find(o => o.label === this.record.status);
      this.stateValue = match ? match.value : null;
    } catch(_e) {
      this.stateOptions = [];
      this.stateValue = null;
    }

    // owner options for admins (support only)
    this.ownerId = this.record.ownerId;
    if (this.isAdmin && this.record.type === 'Support Request') {
      if (this._ownerOptsLoadedFor !== this.record.id) {
        try{
          const list = await getSupportOwnerOptions();
          this.ownerOptions = (list || []).map(x => ({ label: x.name, value: x.id }));
          this._ownerOptsLoadedFor = this.record.id;
        }catch(_e){ /* ignore */ }
      }
    } else {
      this.ownerOptions = [];
      this._ownerOptsLoadedFor = undefined;
    }
  }

  // description edit
  startEditDesc(){ this.editingDesc = true; this.editableHtml = this.record?.descriptionHtml || ''; }
  cancelDesc(){ this.editingDesc = false; this.editableHtml = ''; }
  onDescRteChange(e){ this.editableHtml = e.detail.value || ''; }
  async saveDesc(){
    try{
      const rec = await updateDescription({ id: this.record.id, bodyHtml: this.editableHtml });
      this._record = { ...this.record, descriptionHtml: rec.descriptionHtml };
      this.editingDesc = false;
      this.descSaved = true;
      setTimeout(() => this.descSaved = false, 1600);
      this.dispatchEvent(new CustomEvent('recordupdated'));
    }catch(_e){}
  }

  // state
  onStateChange(e){ this.stateValue = e.detail.value; }

  saveState(){
    this.dispatchEvent(new CustomEvent('savestatus', {
      detail: { id: this.record.id, status: this.stateValue }
    }));
  }

  // owner
  onOwnerChange(e){ this.ownerId = e.detail.value; }
  async saveOwner(){
    try{
      const rec = await updateOwner({ id: this.record.id, ownerId: this.ownerId });
      this._record = { ...this.record, ownerId: rec.ownerId, ownerName: rec.ownerName };
      this.ownerSaved = true;
      setTimeout(() => this.ownerSaved = false, 1600);
      this.dispatchEvent(new CustomEvent('recordupdated'));
    }catch(_e){}
  }

  // comments
  onComposer(e){ this.composer = e.detail.value || ''; }
  post(){
    const text = (this.composer || '').trim();
    if (!text) return;
    this.dispatchEvent(new CustomEvent('postcomment', {
      detail: { id: this.record.id, body: text }
    }));
    this.composer = '';
  }

  // utils
  _formatWhen(dt){
    try {
      const d = new Date(dt);
      return new Intl.DateTimeFormat('en-US', {
        month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'
      }).format(d);
    } catch(_) { return ''; }
  }

  // modal helpers
  close(){ this.dispatchEvent(new CustomEvent('close')); }
  backdropClose(e){ if (e.target.classList.contains('bb-backdrop')) this.close(); }
  stop(e){ e.stopPropagation(); }
}
