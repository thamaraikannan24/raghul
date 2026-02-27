import { LightningElement, wire } from 'lwc';
import { MessageContext, subscribe, unsubscribe, APPLICATION_SCOPE } from 'lightning/messageService';
import SCV_CALL_STATE from '@salesforce/messageChannel/SCV_CallState__c';

export default class CallContext extends LightningElement {
    subscription;
    voiceCallId = 'Waiting...';
    interactionId = 'Waiting...';
    callState = 'IDLE';
    lastUpdated = 'N/A';

    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        this.subscribeToCallState();
    }

    disconnectedCallback() {
        this.unsubscribeFromCallState();
    }

    subscribeToCallState() {
        if (this.subscription) {
            return;
        }
        this.subscription = subscribe(
            this.messageContext,
            SCV_CALL_STATE,
            (message) => this.handleCallEvent(message),
            { scope: APPLICATION_SCOPE }
        );
    }

    unsubscribeFromCallState() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = null;
        }
    }

    handleCallEvent(message) {
        this.voiceCallId = message?.voiceCallId || this.voiceCallId;
        this.interactionId = message?.interactionId || this.interactionId;
        this.callState = message?.callState || this.callState;
        this.lastUpdated = message?.timestamp || new Date().toISOString();
    }
}
