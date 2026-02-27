public with sharing class VoiceCallTriggerHandler {
    @TestVisible
    private static Boolean bypassLinking = false;

    public void beforeInsert(List<VoiceCall> newRecords) {
        enrichFromTelephonyPayload(newRecords);
        if (!bypassLinking) {
            linkVoiceCallsToContacts(newRecords);
        }
    }

    public void beforeUpdate(List<VoiceCall> newRecords, Map<Id, VoiceCall> oldMap) {
        enrichFromTelephonyPayload(newRecords);
    }

    public void afterInsert(List<VoiceCall> newRecords) {
        // Reserved for optional eventing.
    }

    @TestVisible
    private static void enrichFromTelephonyPayload(List<VoiceCall> records) {
        for (VoiceCall vc : records) {
            String payloadRaw = (String) vc.get('IntegrationPayload__c');
            if (String.isBlank(payloadRaw)) {
                continue;
            }

            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(payloadRaw);

            putIfPresent(vc, 'InteractionId__c', payload, 'interactionId');
            putIfPresent(vc, 'TTEC_Segment__c', payload, 'ttecSegment');
            putIfPresent(vc, 'Journey_Phase__c', payload, 'journeyPhase');
            putIfPresent(vc, 'Queue_Name__c', payload, 'queueName');
            putIfPresent(vc, 'Preferred_Language__c', payload, 'language');

            if (payload.containsKey('ani') && payload.get('ani') != null && String.isBlank((String) vc.get('FromPhoneNumber'))) {
                vc.put('FromPhoneNumber', normalizePhone((String) payload.get('ani')));
            }
        }
    }

    @TestVisible
    private static void linkVoiceCallsToContacts(List<VoiceCall> records) {
        Set<String> candidatePhones = new Set<String>();
        for (VoiceCall vc : records) {
            String fromPhone = normalizePhone((String) vc.get('FromPhoneNumber'));
            if (String.isNotBlank(fromPhone)) {
                candidatePhones.add(fromPhone);
            }
        }
        if (candidatePhones.isEmpty()) {
            return;
        }

        List<Contact> contacts = [
            SELECT Id, AccountId, Phone, MobilePhone, OtherPhone
            FROM Contact
            WHERE Phone IN :candidatePhones
               OR MobilePhone IN :candidatePhones
               OR OtherPhone IN :candidatePhones
        ];

        Map<String, List<Contact>> byPhone = new Map<String, List<Contact>>();
        for (Contact c : contacts) {
            for (String phoneValue : new List<String>{c.Phone, c.MobilePhone, c.OtherPhone}) {
                String normalized = normalizePhone(phoneValue);
                if (String.isBlank(normalized)) {
                    continue;
                }
                if (!byPhone.containsKey(normalized)) {
                    byPhone.put(normalized, new List<Contact>());
                }
                byPhone.get(normalized).add(c);
            }
        }

        for (VoiceCall vc : records) {
            String normalizedCaller = normalizePhone((String) vc.get('FromPhoneNumber'));
            if (String.isBlank(normalizedCaller) || !byPhone.containsKey(normalizedCaller)) {
                continue;
            }

            List<Contact> matches = byPhone.get(normalizedCaller);
            if (matches.size() == 1) {
                Contact matched = matches[0];
                vc.put('ContactId', matched.Id);
                vc.put('AccountId', matched.AccountId);
                vc.put('RelatedRecordId', matched.Id);
                vc.put('Needs_Manual_Match__c', false);
            } else {
                vc.put('Needs_Manual_Match__c', true);
            }
        }
    }

    private static void putIfPresent(SObject target, String fieldName, Map<String, Object> payload, String key) {
        if (payload.containsKey(key) && payload.get(key) != null) {
            target.put(fieldName, String.valueOf(payload.get(key)));
        }
    }

    @TestVisible
    private static String normalizePhone(String sourcePhone) {
        if (String.isBlank(sourcePhone)) {
            return null;
        }

        String digits = sourcePhone.replaceAll('[^0-9]', '');
        if (digits.length() == 10) {
            return '+1' + digits;
        }
        if (digits.length() == 11 && digits.startsWith('1')) {
            return '+' + digits;
        }
        if (sourcePhone.startsWith('+')) {
            return sourcePhone;
        }
        return '+' + digits;
    }
}
