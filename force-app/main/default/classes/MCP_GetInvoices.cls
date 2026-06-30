public with sharing class MCP_GetInvoices {

    // INPUT
    public class Request {
        @InvocableVariable
        public String customerId;

        @InvocableVariable
        public String status;
    }

    // OUTPUT
    public class Response {
        @InvocableVariable
        public String formattedOutput;
    }

    @InvocableMethod(label='Get Invoices from Databricks')
    public static List<Response> getInvoices(List<Request> requests) {

        List<Response> responses = new List<Response>();

        for (Request reqInput : requests) {

            System.debug(' MCP CALLED');
            System.debug('CustomerId: ' + reqInput.customerId);
            System.debug('Status: ' + reqInput.status);

            Response wrapper = new Response();
            String outputText = '';

            try {

                //  VALIDATION
                if (String.isBlank(reqInput.customerId) && String.isBlank(reqInput.status)) {
                    wrapper.formattedOutput = 'Please provide a customer ID or invoice status.';
                    responses.add(wrapper);
                    continue;
                }

                Http http = new Http();
                HttpRequest request = new HttpRequest();

                request.setEndpoint('callout:Databricks_API/api/2.0/sql/statements/');
                request.setMethod('POST');
                request.setHeader('Content-Type', 'application/json');
                request.setTimeout(120000);

                //  DYNAMIC QUERY
                String query =
                    'SELECT invoice_id, customer_id, amount, status, invoice_date ' +
                    'FROM dbx_agentforce_invoice_dev.agentforce_db.invoices WHERE 1=1';

                if (!String.isBlank(reqInput.customerId)) {
                    query += ' AND customer_id = \'' + reqInput.customerId + '\'';
                }

                if (!String.isBlank(reqInput.status)) {
                    String normalizedStatus = reqInput.status.trim().toUpperCase();
                    query += ' AND UPPER(status) = \'' + normalizedStatus + '\'';
                }

                System.debug(' FINAL QUERY: ' + query);

                String body = JSON.serialize(new Map<String, Object>{
                    'statement' => query,
                    'warehouse_id' => '177d6dab760fdf91',
                    'wait_timeout' => '50s',
                    'on_wait_timeout' => 'CONTINUE'
                });

                request.setBody(body);

                HttpResponse res = http.send(request);

                //  CRITICAL DEBUG
                System.debug('STATUS CODE: ' + res.getStatusCode());
                System.debug('STATUS TEXT: ' + res.getStatus());
                System.debug('FULL RESPONSE: ' + res.getBody());

                //  HANDLE NON-200
                if (res.getStatusCode() != 200) {
                    outputText = 'HTTP ERROR: ' + res.getStatusCode() + ' - ' + res.getBody();
                    wrapper.formattedOutput = outputText;
                    responses.add(wrapper);
                    continue;
                }

                Map<String, Object> parsed =
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

                if (parsed == null) {
                    wrapper.formattedOutput = 'Error: Empty response from Databricks';
                    responses.add(wrapper);
                    continue;
                }

                //  CHECK QUERY STATUS
                Map<String, Object> statusMap =
                    (Map<String, Object>) parsed.get('status');

                if (statusMap != null) {
                    System.debug('Query State: ' + statusMap.get('state'));
                }

                Map<String, Object> result =
                    (Map<String, Object>) parsed.get('result');

                // ️ ASYNC CASE
                if (result == null) {
                    wrapper.formattedOutput = 'Query is still running. Please try again.';
                    responses.add(wrapper);
                    continue;
                }

                List<Object> rows =
                    (List<Object>) result.get('data_array');

                if (rows == null || rows.isEmpty()) {
                    outputText = 'No invoices found for given criteria.';
                } else {

                    outputText = 'Invoices:\n\n';

                    for (Object rowObj : rows) {

                        List<Object> cols = (List<Object>) rowObj;

                        if (cols == null || cols.size() < 5) continue;

                        outputText +=
                            'Invoice ID: ' + String.valueOf(cols[0]) + '\n' +
                            'Customer ID: ' + String.valueOf(cols[1]) + '\n' +
                            'Amount: ₹' + String.valueOf(cols[2]) + '\n' +
                            'Status: ' + String.valueOf(cols[3]) + '\n' +
                            'Date: ' + String.valueOf(cols[4]) + '\n\n';
                    }
                }

            } catch (Exception e) {

                //  FULL ERROR VISIBILITY (CRITICAL FIX)
                System.debug(' ERROR MESSAGE: ' + e.getMessage());
                System.debug(' STACK TRACE: ' + e.getStackTraceString());

                outputText = 'ERROR: ' + e.getMessage();
            }

            if (String.isBlank(outputText)) {
                outputText = 'No invoices found.';
            }

            wrapper.formattedOutput = outputText.trim();
            responses.add(wrapper);
        }

        return responses;
    }
}