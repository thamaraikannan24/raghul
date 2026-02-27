@IsTest
private class TelephonyIntegrationServiceTest {
    @IsTest
    static void testValidationFailureWithoutInteractionId() {
        TelephonyIntegrationService.HandshakeRequest req = new TelephonyIntegrationService.HandshakeRequest();
        req.eventType = 'CALL_INIT';

        Test.startTest();
        TelephonyIntegrationService.HandshakeResponse res = TelephonyIntegrationService.processEvent(req);
        Test.stopTest();

        System.assertEquals(false, res.success);
        System.assertEquals('interactionId is required', res.message);
    }

    @IsTest
    static void testBuildPayload() {
        TelephonyIntegrationService.HandshakeRequest req = new TelephonyIntegrationService.HandshakeRequest();
        req.interactionId = 'int-1';
        req.eventType = 'CALL_CONNECTED';
        req.callState = 'CONNECTED';
        req.ani = '+14155550100';
        req.dnis = '+14155550200';
        req.genesys__conversationId = 'gcv-1';
        req.payload = '{"k":"v"}';

        String payload = TelephonyIntegrationService.buildPayload(req);
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(payload);

        System.assertEquals('int-1', parsed.get('interactionId'));
        System.assertEquals('CALL_CONNECTED', parsed.get('eventType'));
        System.assertEquals('CONNECTED', parsed.get('callState'));
        System.assertEquals('gcv-1', parsed.get('genesys__conversationId'));
        System.assert(parsed.containsKey('raw'));
    }

    @IsTest
    static void testHttpPostInvalidPayload() {
        RestRequest request = new RestRequest();
        request.requestBody = Blob.valueOf('{"eventType":"CALL_INIT"}');
        request.httpMethod = 'POST';
        RestContext.request = request;

        Test.startTest();
        TelephonyIntegrationService.HandshakeResponse res = TelephonyIntegrationService.handleEvent();
        Test.stopTest();

        System.assertEquals(false, res.success);
    }
}
