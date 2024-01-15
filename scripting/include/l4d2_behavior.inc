#if defined _behavior_included
 #endinput
#endif

#define _behavior_included

enum IAssignment
{
	WITCH_QUERY = 0,
	INFECTED_QUERY,
	SURVIVOR_QUERY,
	SPECIAL_QUERY
};

//enum IBehaviorProperties: (+= 0x4)
enum IActionProperties
{
	m_behavior = 0x8,
	m_parent = 0xC,
	m_child = 0x10,
	m_buriedUnderMe = 0x14,
	m_coveringMe = 0x18,
	m_type = 0x1C,
	m_action = 0x20,
	m_priority = 0x2C,
	m_isStarted = 0x30,
	m_isSuspended = 0x31
};

enum ActionResultType
{ 
	CONTINUE,			// continue executing this action next frame - nothing has changed
	CHANGE_TO,			// change actions next frame
	SUSPEND_FOR,			// put the current action on hold for the new action
	DONE,				// this action has finished, resume suspended action
	SUSTAIN,				// for use with event handlers - a way to say "It's important to keep doing what I'm doing"
};

enum EventResultPriorityType
{
	RESULT_NONE,			// no result
	RESULT_TRY,			// use this result, or toss it out, either is ok
	RESULT_IMPORTANT,		// try extra-hard to use this result
	RESULT_CRITICAL		// this result must be used - emit an error if it can't be
};

enum BehaviorAction
{
	INVALID_ACTION
};

enum struct IActionResult
{
	ActionResultType m_type;
	BehaviorAction m_action;
	EventResultPriorityType m_priority;
	
	Address retn;
	
	void FromAddr (Address retn)
	{
		this.retn = retn;
		
		this.m_type = view_as<ActionResultType>(RDereference(retn, 0));
		this.m_action = view_as<BehaviorAction>(RDereference(retn, 4));
		this.m_priority = view_as<EventResultPriorityType>(RDereference(retn, 12));
	}
	
	void Init (ActionResultType typea, BehaviorAction action, EventResultPriorityType priority = RESULT_TRY)
	{
		this.m_type = typea;
		this.m_action = action;
		this.m_priority = priority;
	}
	
	void Set (Address retn)
	{	
		StoreToAddress(retn + view_as<Address>(4), view_as<int>(this.m_action), NumberType_Int32);
		StoreToAddress(retn + view_as<Address>(12), view_as<int>(this.m_priority), NumberType_Int32);
		
		StoreToAddress(retn, view_as<int>(this.m_type), NumberType_Int32);
	}
	
	void ForAction (BehaviorAction action)
	{	
		StoreToAddress(view_as<Address>(action) + view_as<Address>(view_as<int>(m_action) + 4), view_as<int>(this.m_action), NumberType_Int32);
		StoreToAddress(view_as<Address>(action) + view_as<Address>(view_as<int>(m_type) + 4), view_as<int>(this.m_type), NumberType_Int32);
		StoreToAddress(view_as<Address>(action) + view_as<Address>(view_as<int>(m_priority) + 4), view_as<int>(this.m_priority), NumberType_Int32);
	}
	
	void ToAction (BehaviorAction action)
	{
		this.ForAction(action);
	}
		
	void Apply ()
	{
		this.Set(this.retn);
	}
	
	void GetTypeName ( char[] buffer, int length )
	{
		switch ( this.m_type )
		{
			case CHANGE_TO:		strcopy(buffer, length, "CHANGE_TO");
			case SUSPEND_FOR:	strcopy(buffer, length, "SUSPEND_FOR");
			case DONE:			strcopy(buffer, length, "DONE");
			case SUSTAIN:		strcopy(buffer, length, "SUSTAIN");

			default:			strcopy(buffer, length, "CONTINUE");
		}
	}
}

enum struct IContext
{
	int survivor;
	int special;
	int witch;
	int infected;
}

static IContext context;

methodmap Behavior
{
	public static Behavior ToBehavior(Address entity, IAssignment assign)
	{
		if ( !context.survivor )
		{
			GameData data = new GameData("l4d2_behavior");
			
			context.special = data.GetOffset("g_iSpecial");
			context.survivor = data.GetOffset("g_iSurvivor");
			context.witch = data.GetOffset("g_iWitch");
			context.infected = data.GetOffset("g_iInfected");
			
			delete data;
		}
		
		static const int byte[] =
		{
			0, 0x1C
		};
		
		int offs;
		
		switch(assign)
		{
			case WITCH_QUERY: offs = context.witch;
			case INFECTED_QUERY: offs = context.infected;
			case SURVIVOR_QUERY: offs = context.survivor;
			case SPECIAL_QUERY: offs = context.special;
		}
		
		Address behavior = view_as<Address>(offs) + entity;
		
		for (int i; i < sizeof byte; i++)
			behavior = RDereference(behavior, byte[i]);
		
		return view_as<Behavior>(behavior);
	}
	
	public Behavior (int entity, IAssignment assign)
    {
		return Behavior.ToBehavior(GetEntityAddress(entity), assign);
    }
	
	property Address ToAddress 
	{ 
		public get()
		{
			return view_as<Address>(this);  
		}
	}
	
	property Address AsAddress 
	{ 
		public get()
		{
			return this.ToAddress;
		}
	}
	
	property bool Valid 
	{ 
		public get()
		{
			return this.ToAddress != Address_Null;  
		}
	}
	
	property BehaviorAction CurrentAction
    {
        public get()
        {
            return view_as<BehaviorAction>(RDereference(this.AsAddress, view_as<int>(m_behavior)));
        }
    }
}

methodmap BehaviorAction < Behavior
{
	public Address GetProperty (IActionProperties propertie, NumberType type = NumberType_Int32)
	{ 
		return RDereference(this.ToAddress, view_as<int>(propertie), type);
	}
	
	public void SetProperty (IActionProperties propertie, any value, NumberType type = NumberType_Int32)
	{ 
		StoreToAddress(this.ToAddress, value, type);
	}
	
	property BehaviorAction Next
    {
        public get()
        {
            return view_as<BehaviorAction>(this.GetProperty(m_child));
        }
    }
	
	property BehaviorAction Prev
    {
        public get()
        {
            return view_as<BehaviorAction>(this.GetProperty(m_parent));
        }
    }
	
	property BehaviorAction Under
    {
        public get()
        {
            return view_as<BehaviorAction>(this.GetProperty(m_buriedUnderMe));
        }
    }
	
	property BehaviorAction Above
    {
        public get()
        {
            return view_as<BehaviorAction>(this.GetProperty(m_coveringMe));
        }
    }
	
	property Behavior Contain
    {
        public get()
        {
            return view_as<BehaviorAction>(this.GetProperty(m_behavior));
        }
    }
	
	property BehaviorAction Last
    {
        public get()
        {	
			BehaviorAction action = this;
			
			while ( action.Next.Valid )
				action = action.Next; 
			
			return action;
        }
    }
	
	property BehaviorAction First
    {
        public get()
        {
			BehaviorAction action = this;
			
			while ( action.Prev.Valid )
				action = action.Prev; 
			
			return action;
        }
    }
	
	public void SetAction (IActionResult result)
	{
		this.SetProperty(m_action, result.m_action);
		this.SetProperty(m_priority, result.m_priority);
		this.SetProperty(m_type, result.m_type);
	}
	
	public void GetName(char[] destination, int length)
	{
		static Handle call;
	
		if ( !call )
		{
			int idx = (context.special == 17176 ? 41 : 40);
			
			StartPrepSDKCall(SDKCall_Raw);
			PrepSDKCall_SetVirtual(idx);
			PrepSDKCall_SetReturnInfo(SDKType_String, SDKPass_Pointer);
			call = EndPrepSDKCall();
		}
		
		SDKCall(call, this, destination, length);
	}
	
	public void GetFullName(char[] destination, int length)
	{
		static Handle call;
	
		if ( !call )
		{
			int idx = (context.special == 17176 ? 43 : 42);
			
			StartPrepSDKCall(SDKCall_Raw);
			PrepSDKCall_SetVirtual(idx);
			PrepSDKCall_SetReturnInfo(SDKType_String, SDKPass_Pointer);
			call = EndPrepSDKCall();
		}
		
		SDKCall(call, this, destination, length);
	}
}

/**
 * 	Allocates memory
 *
 * @param		size 		allocation size in bytes
 * @return		allocation address
 */
native Address AllocateMemory (int size);

/**
 * 	Deallocates memory
 *
 * @param		mem 		allocation address
 */
native void DeallocateMemory (Address mem);

stock Address RDereference (Address ptr, int offset = 0, NumberType type = NumberType_Int32) { return view_as<Address>(LoadFromAddress(ptr + view_as<Address>(offset), type)); }