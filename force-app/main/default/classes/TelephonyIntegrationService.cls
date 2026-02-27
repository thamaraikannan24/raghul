@RestResource(urlMapping='/genesys/v1/voice-events/*')
global with sharing class TelephonyIntegrationService {
    global class HandshakeRequest {
        public String interactionId;
        public String eventType;
        public String callState;
        public String ani;
        public String dnis;
        public String genesys__conversationId;
        public String payload;
    }

    global class HandshakeResponse {
        public Boolean success;
        public String message;
        public String voiceCallId;
    }

    @HttpPost
    global static HandshakeResponse handleEvent() {
        RestRequest req = RestContext.request;
        HandshakeRequest eventRequest =
            (HandshakeRequest) JSON.deserialize(req.requestBody.toString(), HandshakeRequest.class);

        return processEvent(eventRequest);
    }

    @TestVisible
    static HandshakeResponse processEvent(HandshakeRequest eventRequest) {
        HandshakeResponse response = new HandshakeResponse();

        if (eventRequest == null || String.isBlank(eventRequest.interactionId)) {
            response.success = false;
            response.message = 'interactionId is required';
            return response;
        }

        List<VoiceCall> existing = [
            SELECT Id, InteractionId__c, FromPhoneNumber, IntegrationPayload__c
            FROM VoiceCall
            WHERE InteractionId__c = :eventRequest.interactionId
            LIMIT 1
        ];

        VoiceCall vc = existing.isEmpty() ? new VoiceCall() : existing[0];
        vc.put('InteractionId__c', eventRequest.interactionId);
        vc.put('FromPhoneNumber', eventRequest.ani);
        vc.put('VendorCallKey', eventRequest.genesys__conversationId);
        vc.put('CallType', 'Inbound');
        vc.put('IntegrationPayload__c', buildPayload(eventRequest));

        if (String.isNotBlank(eventRequest.callState)) {
            vc.put('CallDisposition', eventRequest.callState);
        }

        upsert vc InteractionId__c;

        response.success = true;
        response.message = 'Processed';
        response.voiceCallId = vc.Id;
        return response;
    }

    @TestVisible
    static String buildPayload(HandshakeRequest eventRequest) {
        Map<String, Object> payload = new Map<String, Object>{
            'interactionId' => eventRequest.interactionId,
            'eventType' => eventRequest.eventType,
            'callState' => eventRequest.callState,
            'ani' => eventRequest.ani,
            'dnis' => eventRequest.dnis,
            'genesys__conversationId' => eventRequest.genesys__conversationId
        };
        if (String.isNotBlank(eventRequest.payload)) {
            payload.put('raw', eventRequest.payload);
        }
        return JSON.serialize(payload);
    }
}
