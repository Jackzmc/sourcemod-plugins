#if defined _editor_included_
  #endinput
#endif
#define _editor_included_

public SharedPlugin __pl_editor_ = {
	name = "editor",
	file = "hats.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_editor__SetNTVOptional()
{
	MarkNativeAsOptional("SpawnSchematic");
	MarkNativeAsOptional("StartEdit");
	MarkNativeAsOptional("StartSpawner");
	MarkNativeAsOptional("CancelEdit");
	MarkNativeAsOptional("IsEditorActive");

	MarkNativeAsOptional("StartSelector");
	MarkNativeAsOptional("CancelSelector");
	MarkNativeAsOptional("IsSelectorActive");

	MarkNativeAsOptional("Selector.Count.get");
	MarkNativeAsOptional("Selector.Active.get");
	MarkNativeAsOptional("Selector.Start");
	MarkNativeAsOptional("Selector.SetOnEnd");
	MarkNativeAsOptional("Selector.SetOnPreSelect");
	MarkNativeAsOptional("Selector.SetOnPostSelect");
	MarkNativeAsOptional("Selector.SetOnUnselect");
	MarkNativeAsOptional("Selector.AddEntity");
	MarkNativeAsOptional("Selector.RemoveEntity");
	MarkNativeAsOptional("Selector.Cancel");
	MarkNativeAsOptional("Selector.End");
}
#endif


native bool SpawnSchematic(const char name[32], const float pos[3], const float angles[3] = NULL_VECTOR);

/** Called when edit is done or cancelled
 * @param client - client doing the edit
 * @param entity - The entity edited 
 * @param result - Result of the edit, or cancelled
 * @return boolean - only for StartSpawner, true to continue, false to end spawning
 */
typeset EditorDoneCallback {
	function void (int client, int entity, CompleteType result);
	function bool (int client, int entity, CompleteType result);
}

/** Called when an item is to be selected.
 * @return boolean - TRUE to allow item to be selected, FALSE to reject
 */
typedef SelectPreAddCallback = function bool (int client, int entity);
/** Called when an item has been selected */
typedef SelectPostAddCallback = function void (int client, int entity);

/** Called when an item is to be unselected. */
typedef SelectRemoveCallback = function void (int client, int entity);
/** Called when a user is done selecting items
 * @param client - client doing the selection
 * @param entities - if null, selection was cancelled. if not null, contains list of entity references, must be deleted.
 */
typedef SelectDoneCallback = function void (int client, ArrayList entities);

/** Starts editing an entity
 * @param client - The client that is editing
 * @param entity - The entity to edit
 * @param doneCallback - Called when edit is done
 */
native void StartEdit(int client, int entity, EditorDoneCallback doneCallback);
/** Let client pick prop(s) to spawn
 * @param client - The client that is editing
 * @param entity - The entity to edit
 * @param doneCallback - Called when edit is done
 */
native void StartSpawner(int client, EditorDoneCallback doneCallback);
native void CancelEdit(int client);
// Includes non-plugin started edits
native bool IsEditorActive(int client);

/** Starts a selection, where the client can click on entities to select or deselect them.
 * @param client - the client that can select
 * @param callback - called when user is done seleting or cancelled
 * @param highlightColor - the color to highlight selected items, default solid green
 * @param maxEntities - the max number of selections, 0 for infinite
 */
native void StartSelector(int client, SelectDoneCallback callback, int highlightColor[3] = { 0, 255, 0 }, int maxEntities = 0);

methodmap EntitySelector {
	public EntitySelector(int client) {
		return view_as<EntitySelector>(client);
	}

	public static EntitySelector FromClient(int client) {
		return view_as<EntitySelector>(client);
	}

	/** Starts a new selector for client
	 * @param highlightColor - the color to highlight selected items, default solid green
	 * @param flags - not used. 
	 * @param maxEntities - the max number of selections, 0 for infinite
	 */
	public native EntitySelector Start(int highlightColor[3], int flags = 0, int maxEntities = 0);


	property int Count {
		/** Returns the number of entities in selector. Returns -1 if not active */
		public native get();
	} 

	property bool Active {
		public native get();
	}

	/** Sets the callback for when the selector is ended (or cancelled) */
	public native void SetOnEnd(SelectDoneCallback callback);

	/** Sets the callback for when an item is to be added to the selector.  */
	public native void SetOnPreSelect(SelectPreAddCallback callback);

	/** Sets the callback for when an item has been added to the selector.  */
	public native void SetOnPostSelect(SelectPostAddCallback callback);

	/** Sets the callback for when an item is removed from selector.  */
	public native void SetOnUnselect(SelectRemoveCallback callback);
	
	/** Adds an entity to selection. Does not call SelectAddCallback */
	public native void AddEntity(int entity);

	/** Removes an entity from selection. Does not call SelectAddCallback */
	public native void RemoveEntity(int entity);

	public native void Cancel();

	public native void End();
}


native void CancelSelector(int client);
native bool IsSelectorActive(int client);

enum CompleteType {
	Complete_WallSuccess,
	Complete_WallError,
	Complete_PropSpawned,
	Complete_PropError,
	Complete_EditSuccess
}
