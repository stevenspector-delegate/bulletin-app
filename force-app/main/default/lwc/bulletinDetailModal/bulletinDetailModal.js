import { LightningElement, api, track } from 'lwc';

export default class BulletinDetailModal extends LightningElement {
  @api open = false;
  @api record;         // RequestDto
  @api comments = [];  // CommentDto[]
  @api statusSaved = false; // toggled by parent when updateStatus succeeds

  @track newComment = '';
  _status = '';
  _prevCommentCount = 0;

  renderedCallback(){
    // Inject rich-text Description
    if(this.record && this.template){
      const el = this.template.querySelector('.desc');
      if(el){ el.innerHTML = this.record.descriptionHtml || ''; }
    }
    // Auto-scroll comments when new items arrive
    const count = (this.comments || []).length;
    if(count !== this._prevCommentCount){
      const thr = this.template.querySelector('.thread');
      if(thr){ thr.scrollTop = thr.scrollHeight; }
      this._prevCommentCount = count;
    }
  }

  get titleText(){
    return this.record ? `${this.record.recordNumber} · ${this.record.title}` : 'Record Detail';
  }
  get statusLabel(){ return this.record?.type === 'Suggestion' ? 'Decision' : 'Status'; }
  get statusOptions(){
    const isSug = this.record?.type === 'Suggestion';
    const vals = isSug ? ['Under Review','Accepted','Rejected','Implemented']
                       : ['New','In Review','In Progress','Done','Closed'];
    return vals.map(v => ({ label:v, value:v }));
  }
  get statusValue(){ return this._status || this.record?.status; }

  onStatus(e){ this._status = e.detail.value; }
  save(){
    this.dispatchEvent(new CustomEvent('savestatus', { detail: { id: this.record.id, status: this.statusValue }}));
  }

  onComment(e){ this.newComment = e.detail.value; }
  post(){
    const body = (this.newComment || '').trim();
    if(!body) return;
    this.dispatchEvent(new CustomEvent('postcomment', { detail: { id: this.record.id, body } }));
    this.newComment = '';
  }

  close(){ this.dispatchEvent(new CustomEvent('close')); }
  closeIfBackdrop(e){ if(e.target.classList.contains('backdrop')) this.close(); }
  stop(e){ e.stopPropagation(); }
}
