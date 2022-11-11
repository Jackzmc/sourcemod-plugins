#if defined _ted_included_
	#endinput
#endif
#define _ted_included_

#define VERSION 		"0.1.1"


/**
 * Sets the value of a netprop.
 *
 * @param client		Client with a selected entity.
 * @param sNetprop      Netprop name.
 * @param sValue		Value to set the netprop to.
 * @return              True on success.
 */
native TED_SetNetprop(client, const String:sNetprop[], const String:sValue[]);

/**
 * Sets the selected entity for a client.
 *
 * @param client		Client to select the entity
 * @param sNetprop      Entity index
 * @return              True on success.
 */
native TED_SelectEntity(client, entity);

/**
 * Adds a netprop to the ignore list of a specific client.
 * The client is being notified through TED_OnNetpropHint().
 *
 * @param client		This clients ignore list will be changed.
 * @param sNetprop      Name of the netprop to be ignored, e.g. m_iHealth
 * @return              True on success.
 */
native TED_IgnoreNetprop(client, const String:sNetprop[]);

/**
 * Removes a netprop from the ignore list of a specific client
 * The client is being notified through TED_OnNetpropHint().
 *
 * @param client		This clients ignore list will be changed.
 * @param sNetprop      Name of the netprop to be removed from the list
 * @return              True on success.
 */
native TED_UnignoreNetprop(client, const String:sNetprop[]);

/**
 * Shows all netprops and their values for the selected entity
 * This will feed all information through TED_OnShow().
 *
 * @param client		The client issuing the action. He will see the output.
 * @return              True on success.
 */
native TED_ShowNetprops(client);

/**
 * Repeatedly shows all changed netprops for the selected entity
 * This will feed all information through TED_OnCompare().
 *
 * @param client		The client issuing the action. He will see the output.
 * @return              True on success.
 */
native TED_WatchNetprops(client);

/**
 * Stops watching a entity
 *
 * @param client		The client issuing the action. He will see the output.
 * @return              True on success.
 */
native TED_StopWatchNetprops(client);

/**
 * Saves the current state of netprops for later manual comparison.
 *
 * @param client		The client issuing the action.
 * @return              True on success.
 */
native TED_SaveNetprops(client);

/**
 * Compares the current state of netprops with the saved state and outputs any differences.
 * This will feed all information through TED_OnCompare().
 *
 * @param client		The client issuing the action. He will see the output.
 * @return              True on success.
 */
native TED_CompareNetprops(client);


forward TED_OnCompare(client, const String:sNetprop[], const String:sOld[], const String:sNow[], iOffset);
forward TED_OnNetpropHint(client, const String:sText[], const String:sNetprop[]);
forward TED_OnShow(client, const String:sNetprop[], const String:sValue[], iOffset);
forward TED_OnInfo(client, const String:sText[]);