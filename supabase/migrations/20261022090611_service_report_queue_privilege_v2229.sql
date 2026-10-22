-- Invoker RPC delegates only to the trusted existing private queue helper.
grant execute on function private.enqueue_report_refresh_v2074(text) to service_role;
