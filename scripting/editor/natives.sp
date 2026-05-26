
int Native_StartEdit(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	int entity = GetNativeCell(2);
	Editor[client].Import(entity, false);
	PrivateForward fwd = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	fwd.AddFunction(INVALID_HANDLE, GetNativeFunction(3));
	Editor[client].SetCallback(fwd, true);
	return 0;
}
int Native_StartSpawner(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	g_PropData[client].Selector.Cancel();
	PrivateForward fwd = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	fwd.AddFunction(INVALID_HANDLE, GetNativeFunction(2));
	Editor[client].SetCallback(fwd, false);
	ShowCategoryList(client, ROOT_CATEGORY);
	return 0;
}
int Native_CancelEdit(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	Editor[client].Cancel();
	return 0;
}
int Native_IsEditorActive(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	Editor[client].IsActive();
	return 0;
}

int Native_StartSelector(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	int color[3] = { 0, 255, 0 };
	PrivateForward fwd = new PrivateForward(ET_Single, Param_Cell, Param_Cell);
	fwd.AddFunction(plugin, GetNativeFunction(2));
	GetNativeArray(3, color, 3);
	int limit = GetNativeCell(4);
	g_PropData[client].Selector.Start(color, 0, limit);
	g_PropData[client].Selector.SetOnEnd(fwd);
	return 0;
}
int Native_CancelSelector(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	g_PropData[client].Selector.Cancel();
	return 0;
}
int Native_IsSelectorActive(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	g_PropData[client].Selector.IsActive();
	return 0;
}
int Native_Selector_Start(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	int color[3] = { 0, 255, 0 };
	GetNativeArray(2, color, 3);
	int flags = GetNativeCell(3);
	int limit = GetNativeCell(4);
	g_PropData[client].Selector.Start(color, flags, limit);
	return 0;
}
int Native_Selector_GetCount(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if(!g_PropData[client].Selector.IsActive()) {
		return -1;
	} else {
		return g_PropData[client].Selector.list.Length;
	}
}
int Native_Selector_GetActive(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	return g_PropData[client].Selector.IsActive();
}
int Native_Selector_SetOnEnd(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	PrivateForward fwd = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell);
	fwd.AddFunction(plugin, GetNativeFunction(2));
	g_PropData[client].Selector.SetOnEnd(fwd);
	return 0;
}
int Native_Selector_SetOnPreSelect(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	PrivateForward fwd = new PrivateForward(ET_Single, Param_Cell, Param_Cell);
	if(!fwd.AddFunction(plugin, GetNativeFunction(2))) return 0;
	g_PropData[client].Selector.SetOnPreSelect(fwd);
	return 1;
}
int Native_Selector_SetOnPostSelect(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	PrivateForward fwd = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell);
	if(!fwd.AddFunction(plugin, GetNativeFunction(2))) return 0;
	g_PropData[client].Selector.SetOnPostSelect(fwd);
	return 1;
}
int Native_Selector_SetOnUnselect(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	PrivateForward fwd = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell);
	if(!fwd.AddFunction(plugin, GetNativeFunction(2))) return 0;
	g_PropData[client].Selector.SetOnUnselect(fwd);
	return 1;
}
int Native_Selector_AddEntity(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	int entity = GetNativeCell(2);
	g_PropData[client].Selector.AddEntity(entity, false);
	return 0;
}
int Native_Selector_RemoveEntity(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	int entity = GetNativeCell(2);
	g_PropData[client].Selector.RemoveEntity(entity);
	return 0;
}
int Native_Selector_Cancel(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	g_PropData[client].Selector.Cancel();
	return 0;
}
int Native_Selector_End(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	g_PropData[client].Selector.End();
	return 0;
}