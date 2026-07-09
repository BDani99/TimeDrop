-- handle_new_user() is a trigger function only — it should never be callable
-- as a REST RPC. Triggers fire as part of the triggering statement regardless
-- of function EXECUTE privilege, so revoking these grants keeps the
-- auto-provisioning trigger working while removing it from the exposed API
-- (closes the security advisor's anon_security_definer_function_executable
-- finding).
revoke execute on function public.handle_new_user() from public;
revoke execute on function public.handle_new_user() from anon;
revoke execute on function public.handle_new_user() from authenticated;
