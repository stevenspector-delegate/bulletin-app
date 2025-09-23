import LightningModal from 'lightning/modal';

export default class BulletinSubmitRequestModal extends LightningModal {
    // Optional: pass defaults in via .open({ size, initialType }) if you want
    handleCancel() {
        this.close({ outcome: 'cancel' });
    }
    handleSuccess() {
        this.close({ outcome: 'success' });
    }
}
