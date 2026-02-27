# Technical Design Document (TDD)
## Migration from Legacy Open CTI (TTEC OneView/Genesys) to Salesforce Service Cloud Voice (SCV) Partner Telephony (BYOT)

**Author:** Senior Salesforce Architect & Integration Specialist  
**Version:** 1.0  
**Date:** 2026-02-27  
**Status:** Proposed

---

## 1. Executive Summary

This document defines the target architecture, implementation design, and migration roadmap for replacing the legacy browser-based Open CTI integration (TTEC OneView overlay on Genesys) with **Service Cloud Voice (Partner Telephony/BYOT) using CX Cloud from Genesys and Salesforce**.

The target design shifts from client-driven JavaScript screen pops to a **server-to-server, signal-driven model** where Salesforce-native objects and automation govern routing, context, and agent experience.

Key outcomes:
- Replace Open CTI Task-centric interaction tracking with **VoiceCall** records.
- Drive screen pop and record-association using **Omni-Channel Flow + InteractionId correlation**.
- Enable agent-assist/Agentforce use cases via **real-time transcription**.
- Support controlled deployment using a **dual-run migration strategy**.

---

## 2. Scope

### In Scope
- SCV + Partner Telephony configuration.
- Genesys Cloud OAuth and API trust setup.
- VoiceCall lifecycle, event mapping, and enrichment.
- Omni-Channel Flow logic for caller lookup and VoiceCall linking.
- Real-time transcript ingestion and Einstein Next Best Action triggers.
- Controlled cutover strategy.

### Out of Scope
- Full contact center process redesign.
- Downstream telephony provider replacement.
- Legacy Open CTI feature parity for non-voice channels.

---

## 3. Current vs Future State

### Current State (Legacy)
- Agent runs Salesforce UI + embedded Open CTI softphone (TTEC OneView JS overlay).
- Genesys events consumed in browser via JavaScript API callbacks.
- Screen pop logic executed client-side.
- Interaction persistence centered around **Task** and custom objects.

### Future State (Target)
- Native SCV console with Partner Telephony integration.
- Genesys and Salesforce exchange events **server-to-server**.
- SCV creates and updates **VoiceCall** object as the source of truth.
- Omni-Channel and Flows handle routing/context pop.
- Audio transcription streams in real-time for AI workflows.

---

## 4. Target Architecture (Logical Diagram Narrative)

### 4.1 Components
- **Genesys Cloud CX**
  - Telephony session control and interaction state.
  - CX Cloud connector / Partner Telephony adapter.
  - AudioHook service for transcript streaming.
- **Salesforce Service Cloud Voice (BYOT)**
  - VoiceCall object, Omni-Channel, Flows, SCV Utility.
  - Apex services for enrichment.
  - Voice Transcript + Einstein/NBA.
- **Identity & Trust**
  - OAuth 2.0 Client Credentials between Genesys and Salesforce endpoints.

### 4.2 Server-to-Server Handshake and Event Flow
1. **Inbound call arrives in Genesys Cloud** and is assigned an `interactionId` (conversation/call identifier).
2. Genesys CX Cloud connector sends a **call-init signal** to Salesforce SCV Partner Telephony endpoint.
3. Salesforce validates token/signature and creates a **VoiceCall** record (`Status = Ringing/Queued`) with external correlation attributes (`InteractionId__c`, ANI, queue).
4. Omni-Channel evaluates routing and pushes work to an available agent based on Skills/Presence.
5. On answer/hold/resume/transfer/disconnect, Genesys emits state events server-to-server; Salesforce updates the same VoiceCall.
6. Transcript/audio metadata stream is linked to the active VoiceCall.
7. On wrap-up, Genesys sends final disposition; Salesforce closes VoiceCall and executes post-call automations.

### 4.3 Why VoiceCall Replaces Task
- **Task** is asynchronous/general-purpose activity logging and lacks native voice lifecycle semantics.
- **VoiceCall** supports telephony state transitions, SCV timeline, transcript linkage, and Omni voice UX.
- Real-time events map naturally to VoiceCall updates (ringing, connected, held, transferred, ended) without custom client scripts.

---

## 5. Detailed Configuration

## 5.1 Partner Telephony Contact Center Definition File (XML)

> Note: exact fields vary by managed package/API version. Use this as a baseline template and align tags to your current Salesforce Partner Telephony schema.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ContactCenterDefinition xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Genesys SCV BYOT - Production</label>
    <version>1.0</version>
    <adapterUrl>https://apps.mypurecloud.com/crm/salesforce</adapterUrl>
    <softphoneLayout>ServiceConsole_SCV</softphoneLayout>
    <displayName>Genesys Cloud Voice</displayName>

    <properties>
        <property>
            <name>vendor</name>
            <value>Genesys</value>
        </property>
        <property>
            <name>integrationType</name>
            <value>PartnerTelephony</value>
        </property>
        <property>
            <name>region</name>
            <value>us-east-1</value>
        </property>
        <property>
            <name>oauthClientId</name>
            <value>{{GENESYS_OAUTH_CLIENT_ID}}</value>
        </property>
        <property>
            <name>callbackUrl</name>
            <value>https://login.salesforce.com/services/oauth2/callback</value>
        </property>
        <property>
            <name>voiceCallObjectApiName</name>
            <value>VoiceCall</value>
        </property>
        <property>
            <name>interactionIdField</name>
            <value>InteractionId__c</value>
        </property>
    </properties>
</ContactCenterDefinition>
```

### 5.2 OAuth 2.0 Client Credentials (Genesys -> Salesforce)

1. **Create a Connected App in Salesforce**
   - Enable OAuth settings.
   - Add required scopes (minimum: API access).
   - Set policies for machine-to-machine access.
2. **Create an Integration User**
   - Assign SCV integration permission sets, API Enabled, and object permissions on VoiceCall/transcript custom fields.
3. **Set JWT or Client Credential policy (per org security standard)**
   - Preferred: certificate/JWT assertion where possible.
4. **In Genesys Cloud Admin**
   - Create OAuth client (Client Credentials grant).
   - Store Salesforce token endpoint and audience.
   - Configure secret rotation cadence.
5. **Token acquisition flow**
   - Genesys requests token from Salesforce auth endpoint.
   - Salesforce returns bearer token with scoped permissions.
   - Genesys includes bearer token in Partner Telephony API calls.
6. **Validation & hardening**
   - Restrict integration user login IPs if required.
   - Enable event monitoring and transaction security for anomalous behavior.

---

## 6. Omni-Channel Flow Design (InteractionId Before-Save Lookup)

## 6.1 Objective
Automatically associate incoming VoiceCall to Contact prior to agent acceptance, using Genesys `InteractionId` + caller ANI.

## 6.2 Flow Type
- **Record-Triggered Flow on VoiceCall**
- Trigger: `Before Save` on create/update when `InteractionId__c` is populated.

## 6.3 Flow Logic
1. **Entry Criteria**
   - `ISNEW() = TRUE` OR `ISCHANGED(InteractionId__c)`.
   - `InteractionId__c != null`.
2. **Normalize ANI**
   - Subflow/formula to standardize E.164 format.
3. **Lookup Contact**
   - Query Contact where Phone/Mobile/OtherPhone matches normalized ANI.
   - Optional: use an Interaction Staging custom object keyed by `InteractionId__c` for pre-enrichment.
4. **Decision Branches**
   - One exact match: assign `VoiceCall.ContactId`.
   - Multiple matches: assign to a triage queue and flag `Needs_Manual_Match__c = true`.
   - No match: create case shell or route to “Unknown Caller” flow path.
5. **Before-Save assignments**
   - Set `VoiceCall.RelatedRecordId` (Contact/Case depending on model).
   - Set `VoiceCall.AccountId` from Contact.
   - Persist `InteractionId__c` and queue metadata for analytics.

## 6.4 Result
The VoiceCall opens with context in native SCV without browser-side Open CTI JavaScript.

---

## 7. Apex Technical Components

## 7.1 VoiceCall Trigger Handler (Sample)

```apex
trigger VoiceCallTrigger on VoiceCall (before insert, before update, after insert) {
    VoiceCallTriggerHandler handler = new VoiceCallTriggerHandler();

    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            handler.beforeInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            handler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        handler.afterInsert(Trigger.new);
    }
}

public with sharing class VoiceCallTriggerHandler {

    public void beforeInsert(List<VoiceCall> newRecords) {
        enrichFromTelephonyPayload(newRecords, null);
    }

    public void beforeUpdate(List<VoiceCall> newRecords, Map<Id, VoiceCall> oldMap) {
        enrichFromTelephonyPayload(newRecords, oldMap);
    }

    public void afterInsert(List<VoiceCall> newRecords) {
        // Optional: emit Platform Event for downstream analytics.
    }

    private void enrichFromTelephonyPayload(List<VoiceCall> records, Map<Id, VoiceCall> oldMap) {
        for (VoiceCall vc : records) {
            // Assume telephony connector writes raw JSON into IntegrationPayload__c
            if (String.isNotBlank((String) vc.get('IntegrationPayload__c'))) {
                Map<String, Object> payload =
                    (Map<String, Object>) JSON.deserializeUntyped((String) vc.get('IntegrationPayload__c'));

                // Interaction correlation
                if (payload.containsKey('interactionId')) {
                    vc.put('InteractionId__c', (String) payload.get('interactionId'));
                }

                // TTEC-specific segment enrichment
                if (payload.containsKey('ttecSegment')) {
                    vc.put('TTEC_Segment__c', (String) payload.get('ttecSegment'));
                }
                if (payload.containsKey('journeyPhase')) {
                    vc.put('Journey_Phase__c', (String) payload.get('journeyPhase'));
                }

                // Queue / language attributes
                if (payload.containsKey('queueName')) {
                    vc.put('Queue_Name__c', (String) payload.get('queueName'));
                }
                if (payload.containsKey('language')) {
                    vc.put('Preferred_Language__c', (String) payload.get('language'));
                }
            }
        }
    }
}
```

### 7.2 LMS Channel Definition for SCV State Sync (Sample)

Create message channel metadata:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningMessageChannel xmlns="http://soap.sforce.com/2006/04/metadata">
    <masterLabel>SCV Call State Channel</masterLabel>
    <isExposed>true</isExposed>
    <description>Publishes Service Cloud Voice call state to custom LWCs.</description>
    <lightningMessageFields>
        <fieldName>voiceCallId</fieldName>
        <description>Salesforce VoiceCall record Id</description>
    </lightningMessageFields>
    <lightningMessageFields>
        <fieldName>interactionId</fieldName>
        <description>Genesys interaction id</description>
    </lightningMessageFields>
    <lightningMessageFields>
        <fieldName>callState</fieldName>
        <description>RINGING|CONNECTED|HELD|ENDED</description>
    </lightningMessageFields>
    <lightningMessageFields>
        <fieldName>timestamp</fieldName>
        <description>Event timestamp</description>
    </lightningMessageFields>
</LightningMessageChannel>
```

Recommended API name: `SCV_CallState__c`.

---

## 8. AI & Real-Time Transcription

## 8.1 Genesys AudioHook -> Salesforce Transcript

1. Enable AudioHook monitor in Genesys Architect/flow for target queues.
2. Configure secure WebSocket endpoint for transcript processor (Genesys-managed or middleware).
3. Stream bidirectional audio metadata with `interactionId` correlation key.
4. Map transcript chunks to Salesforce Voice Transcript session associated to VoiceCall.
5. Persist interim and final transcript segments with speaker attribution (Agent/Customer).
6. Enforce PII redaction policies before storage if required by compliance.

## 8.2 Trigger Einstein Next Best Action from Transcript Keywords

1. Define keyword taxonomy (e.g., “cancel”, “supervisor”, “refund”, “fraud”).
2. Create Transcript Insight parser (Flow/Apex) that evaluates live transcript events.
3. Publish a Platform Event `Transcript_Insight__e` with `VoiceCallId`, keyword, confidence.
4. Configure NBA Strategy:
   - Input: active VoiceCall + latest transcript insight.
   - Rules: keyword/intent, customer tier, case severity.
   - Output: recommendation card in agent workspace.
5. Add guardrails:
   - Debounce repeated keyword triggers.
   - Confidence threshold and exclusion lists.

---

## 9. Migration Strategy (Dual-Run)

## 9.1 Principles
- De-risk via phased rollout.
- Preserve service continuity.
- Measure operational parity before full cutover.

## 9.2 Dual-Run Design
- **Cohort A (Pilot Agents):** SCV Partner Telephony.
- **Cohort B (Control Group):** legacy TTEC OneView Open CTI.

Routing split options:
- Queue-based split in Genesys (preferred).
- Agent group mapping by skill/profile.
- Time-windowed canary for peak/off-peak validation.

## 9.3 Execution Phases
1. **Phase 0 - Foundation**
   - Build org config, security, VoiceCall data model, and telemetry dashboards.
2. **Phase 1 - Shadow Validation**
   - Send mirrored metadata events to Salesforce without agent exposure.
3. **Phase 2 - Pilot (5–10% agents)**
   - Enable SCV for selected teams/queues.
   - Keep rollback switch to OneView.
4. **Phase 3 - Expand (25–50%)**
   - Compare AHT, transfer rate, disposition accuracy, transcript quality.
5. **Phase 4 - Full Cutover**
   - Disable Open CTI package dependencies.
   - Finalize support runbooks and hypercare.

## 9.4 Success Metrics
- Screen pop accuracy ≥ 98%.
- VoiceCall/contact auto-link rate ≥ 95%.
- Transcript availability in < 3 seconds from utterance.
- No increase in handle time after stabilization window.

## 9.5 Rollback Plan
- Feature flag at queue/profile level.
- Re-route pilot agents to legacy queue set.
- Suspend AudioHook/NBA processing independently of call handling.

---

## 10. Security, Compliance, and Observability

- Use least-privilege integration user and scoped OAuth tokens.
- Encrypt in transit (TLS 1.2+) and at rest for transcript data.
- Mask sensitive data (PCI/PII) in transcripts and logs.
- Centralize observability:
  - Genesys event delivery success/failure.
  - Salesforce API error rates.
  - VoiceCall state transition anomalies.
- Implement audit trail on automated recommendations shown to agents.

---

## 11. Risks and Mitigations

- **Risk:** Identifier mismatch between Genesys conversation and Salesforce VoiceCall.  
  **Mitigation:** enforce canonical `InteractionId__c` mapping and idempotent upsert logic.

- **Risk:** Transcript latency impacts real-time NBA usefulness.  
  **Mitigation:** asynchronous eventing, threshold-based triggers, fallback static guidance cards.

- **Risk:** Agent adoption issues during UX transition.  
  **Mitigation:** role-based training, pilot champions, side-by-side job aids.

---

## 12. Implementation Roadmap (Indicative)

- **Sprint 1–2:** Environment setup, OAuth trust, Contact Center Definition, baseline VoiceCall model.
- **Sprint 3–4:** Omni before-save flow, trigger handler, event observability dashboards.
- **Sprint 5:** AudioHook + transcript ingestion integration.
- **Sprint 6:** Einstein NBA strategy and keyword triggers.
- **Sprint 7:** Pilot dual-run go-live.
- **Sprint 8+:** Scale-out and legacy decommission.

---

## 13. Appendices

### Appendix A: Recommended Custom Fields on VoiceCall
- `InteractionId__c` (Text, External Id)
- `TTEC_Segment__c` (Picklist/Text)
- `Journey_Phase__c` (Text)
- `Queue_Name__c` (Text)
- `Preferred_Language__c` (Text)
- `Needs_Manual_Match__c` (Checkbox)
- `IntegrationPayload__c` (Long Text Area / Encrypted where required)

### Appendix B: Non-Functional Requirements
- End-to-end event latency target: < 1.5 seconds for state updates.
- 99.9% integration availability during business hours.
- Idempotent event processing with replay support.

