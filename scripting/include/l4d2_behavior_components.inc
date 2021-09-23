#if defined _behavior_components_included
 #endinput
#endif

#define _behavior_components_included

#define E9_LEN 5

enum struct IHookHandler
{
	bool hooked;
	
	int hooklen;
	int memlen;
	
	int original[12];
	
	Address func;
	Address detouraddr;
	Address allocate;
	
	DynamicDetour detour;
	
	void Hook (Address _func, int _hooklen, int _memlen, int offs = 0)
	{
		this.memlen = _memlen;
		this.allocate = AllocateMemory(this.memlen + offs);
		this.func = _func;
		this.hooklen = _hooklen;
		this.detouraddr = this.allocate + view_as<Address>(this.memlen - E9_LEN - _hooklen + offs);

		int i;
		
		for (;i < this.memlen + offs; i++) 
		{
			StoreToAddress(this.allocate + view_as<Address>(i), 0x90, NumberType_Int8);
		}
		
		for (i = 0; i < this.hooklen; i++) 
		{
			this.original[i] = view_as<int>(RDereference(this.func, i, NumberType_Int8));
			StoreToAddress(this.func + view_as<Address>(i), 0x90, NumberType_Int8);
			StoreToAddress(this.detouraddr + view_as<Address>(i), this.original[i], NumberType_Int8);
		}
		
		this.hooked = true;
	}
	
	void Unhook()
	{
		if ( this.hooked )
		{
			for (int i = 0; i < this.hooklen; i++) 
			{
				StoreToAddress(this.func + view_as<Address>(i), this.original[i], NumberType_Int8);
			}
			
			DeallocateMemory(this.allocate);
			this.hooked = false;
		}
	}
}

/**
 * 	Hooks action handler
 *
 * @param		func 		event handler address
 * @param		out 		IHookHandler struct
 */
native void HookActionEvent (Address func, any[] out);