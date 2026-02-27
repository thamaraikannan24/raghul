@IsTest
private class VoiceCallTriggerHandlerTest {
    @IsTest
    static void testEnrichmentAndNormalize() {
        VoiceCall vc = new VoiceCall();
        vc.put('IntegrationPayload__c', '{"interactionId":"abc-123","ttecSegment":"VIP","journeyPhase":"Retention","queueName":"Support","language":"en-US","ani":"(415) 555-1212"}');

        Test.startTest();
        VoiceCallTriggerHandler.enrichFromTelephonyPayload(new List<VoiceCall>{ vc });
        Test.stopTest();

        System.assertEquals('abc-123', (String) vc.get('InteractionId__c'));
        System.assertEquals('VIP', (String) vc.get('TTEC_Segment__c'));
        System.assertEquals('Retention', (String) vc.get('Journey_Phase__c'));
        System.assertEquals('Support', (String) vc.get('Queue_Name__c'));
        System.assertEquals('en-US', (String) vc.get('Preferred_Language__c'));
        System.assertEquals('+14155551212', (String) vc.get('FromPhoneNumber'));

        System.assertEquals('+14155551212', VoiceCallTriggerHandler.normalizePhone('4155551212'));
        System.assertEquals('+14155551212', VoiceCallTriggerHandler.normalizePhone('+14155551212'));
        System.assertEquals(null, VoiceCallTriggerHandler.normalizePhone(null));
    }

    @IsTest
    static void testBeforeInsertWithBypassLinking() {
        VoiceCallTriggerHandler.bypassLinking = true;
        VoiceCall vc = new VoiceCall();
        vc.put('IntegrationPayload__c', '{"interactionId":"evt-001"}');

        Test.startTest();
        new VoiceCallTriggerHandler().beforeInsert(new List<VoiceCall>{ vc });
        Test.stopTest();

        System.assertEquals('evt-001', (String) vc.get('InteractionId__c'));
        VoiceCallTriggerHandler.bypassLinking = false;
    }
}
