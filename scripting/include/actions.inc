#if defined _actions_included
 #endinput
#endif

#define _actions_included

#define ACTION_NAME_LENGTH 32

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

typedef ActionsIteratorCallback = function void (BehaviorAction action);

/* OnActionCreated is called when action added to Behavior system */
forward void OnActionCreated( BehaviorAction action, int actor, const char[] name );

/* OnActionDestroyed is called when action is about to be destroyed */
forward void OnActionDestroyed( BehaviorAction action, int actor, const char[] name );

methodmap ActionResult
{
	public native void GetReason( char[] destination, int maxlength );
	public native void SetReason( const char[] reason );
	
	property ActionResultType type
	{
		public native get();
		public native set(ActionResultType type);
	}
	
	property BehaviorAction action
	{
		public native get();
		public native set(BehaviorAction action);
	}
	
	public bool IsRequestingChange()
	{
		ActionResultType type = this.type;
		
		return (type == CHANGE_TO || type == SUSPEND_FOR || type == DONE);
	}
}

methodmap ActionDesiredResult < ActionResult
{
	property EventResultPriorityType priority
	{
		public native get();
		public native set(EventResultPriorityType priority);
	}
}

methodmap BehaviorAction
{
	/* If you want to create game action manually you need to call this function with the appropriate constructor */
	public static native BehaviorAction Allocate( int size );
	
	/* Deallocates action */
	/* Use this when you want to replace some action with you own */
	public static native BehaviorAction Deallocate( BehaviorAction action );
	
	/* Searches for action with given name */
	/* INVALID_ACTION if entity doesn't have this action */
	public static native BehaviorAction Find( int entity, const char[] name );
	
	/* Used to iterate through all entity actions */
	public static native void Actions( int entity, ActionsIteratorCallback callback );
	
	public native int GetName( char[] destination, int maxlength = ACTION_NAME_LENGTH );
	
	/* Just for convenience to make it easier to get/set data from/for action  */
	
	public any Get( int offset, NumberType type = NumberType_Int32 )
	{
		return view_as<any>(LoadFromAddress(view_as<Address>(this) + view_as<Address>(offset), type));
	}
	
	public void Set( int offset, any data, NumberType type = NumberType_Int32 )
	{
		StoreToAddress(view_as<Address>(this) + view_as<Address>(offset), data, type);
	}
	
	/* Action members  */
	
	/* Return parent action */
	property BehaviorAction Parent
	{
		public native get();
	}
	
	/* Return child action */
	property BehaviorAction Child
	{
		public native get();
	}
	
	/* Return Under action */
	/* if we are suspender then this will return a suspended action */
	property BehaviorAction Under
	{
		public native get();
	}
	
	/* Return Above action */
	/* if we are suspended action then this will return a suspender */
	property BehaviorAction Above
	{
		public native get();
	}
	
	/* Gets entity who owns this action */
	/* 0 will be returned if action is not started yet */
	property int Actor
	{
		public native get();
	}
	
	/* Used to determine whether an action has been suspended */
	property bool IsSuspended
	{
		public native get();
		public native set(bool suspended);
	}
	
	/* Used to determine whether an action has been started (OnStart has already been called)*/
	property bool IsStarted
	{
		public native get();
		public native set(bool started);
	}
	
	/* Event Handlers */
	
	property Function OnStart
	{
		public native set(Function func);
	}
	
	property Function OnUpdate
	{
		public native set(Function func);
	}
	
	property Function OnEnd
	{
		public native set(Function func);
	}
	
	property Function OnSuspend
	{
		public native set(Function func);
	}
	
	property Function OnResume
	{
		public native set(Function func);
	}
	
	property Function OnInitialContainedAction
	{
		public native set(Function func);
	}
	
	property Function OnLeaveGround
	{
		public native set(Function func);
	}
	
	property Function OnLandOnGround
	{
		public native set(Function func);
	}
	
	property Function OnContact
	{
		public native set(Function func);
	}
	
	property Function OnMoveToSuccess
	{
		public native set(Function func);
	}
	
	property Function OnMoveToFailure
	{
		public native set(Function func);
	}
	
	property Function OnStuck
	{
		public native set(Function func);
	}
	
	property Function OnUnStuck
	{
		public native set(Function func);
	}
	
	property Function OnPostureChanged
	{
		public native set(Function func);
	}
	
	property Function OnAnimationActivityComplete
	{
		public native set(Function func);
	}
	
	property Function OnAnimationActivityInterrupted
	{
		public native set(Function func);
	}
	
	property Function OnAnimationEvent
	{
		public native set(Function func);
	}
	
	property Function OnIgnite
	{
		public native set(Function func);
	}
	
	property Function OnInjured
	{
		public native set(Function func);
	}
	
	property Function OnKilled
	{
		public native set(Function func);
	}
	
	property Function OnOtherKilled
	{
		public native set(Function func);
	}
	
	property Function OnSight
	{
		public native set(Function func);
	}
	
	property Function OnLostSight
	{
		public native set(Function func);
	}
	
	property Function OnThreatChanged
	{
		public native set(Function func);
	}
	
	property Function OnSound
	{
		public native set(Function func);
	}
	
	property Function OnSpokeConcept
	{
		public native set(Function func);
	}
	
	property Function OnNavAreaChanged
	{
		public native set(Function func);
	}
	
	property Function OnModelChanged
	{
		public native set(Function func);
	}
	
	property Function OnPickUp
	{
		public native set(Function func);
	}
	
	property Function OnShoved
	{
		public native set(Function func);
	}
	
	property Function OnBlinded
	{
		public native set(Function func);
	}
	
	property Function OnEnteredSpit
	{
		public native set(Function func);
	}
	
	property Function OnHitByVomitJar
	{
		public native set(Function func);
	}
	
	property Function OnCommandAttack
	{
		public native set(Function func);
	}
	
	property Function OnCommandAssault
	{
		public native set(Function func);
	}
	
	property Function OnCommandApproachV
	{
		public native set(Function func);
	}
	
	property Function OnCommandApproachE
	{
		public native set(Function func);
	}
	
	property Function OnCommandRetreat
	{
		public native set(Function func);
	}
	
	property Function OnCommandPause
	{
		public native set(Function func);
	}
	
	property Function OnCommandResume
	{
		public native set(Function func);
	}
	
	property Function OnCommandString
	{
		public native set(Function func);
	}
	
	property Function IsAbleToBlockMovementOf
	{
		public native set(Function func);
	}
	
	/**************************/
	/* POST CALLBACKS SETTERS */
	/**************************/
	
	property Function OnStartPost
	{
		public native set(Function func);
	}
	
	property Function OnUpdatePost
	{
		public native set(Function func);
	}
	
	property Function OnEndPost
	{
		public native set(Function func);
	}
	
	property Function OnSuspendPost
	{
		public native set(Function func);
	}
	
	property Function OnResumePost
	{
		public native set(Function func);
	}
	
	property Function OnInitialContainedActionPost
	{
		public native set(Function func);
	}
	
	property Function OnLeaveGroundPost
	{
		public native set(Function func);
	}
	
	property Function OnLandOnGroundPost
	{
		public native set(Function func);
	}
	
	property Function OnContactPost
	{
		public native set(Function func);
	}
	
	property Function OnMoveToSuccessPost
	{
		public native set(Function func);
	}
	
	property Function OnMoveToFailurePost
	{
		public native set(Function func);
	}
	
	property Function OnStuckPost
	{
		public native set(Function func);
	}
	
	property Function OnUnStuckPost
	{
		public native set(Function func);
	}
	
	property Function OnPostureChangedPost
	{
		public native set(Function func);
	}
	
	property Function OnAnimationActivityCompletePost
	{
		public native set(Function func);
	}
	
	property Function OnAnimationActivityInterruptedPost
	{
		public native set(Function func);
	}
	
	property Function OnAnimationEventPost
	{
		public native set(Function func);
	}
	
	property Function OnIgnitePost
	{
		public native set(Function func);
	}
	
	property Function OnInjuredPost
	{
		public native set(Function func);
	}
	
	property Function OnKilledPost
	{
		public native set(Function func);
	}
	
	property Function OnOtherKilledPost
	{
		public native set(Function func);
	}
	
	property Function OnSightPost
	{
		public native set(Function func);
	}
	
	property Function OnLostSightPost
	{
		public native set(Function func);
	}
	
	property Function OnThreatChangedPost
	{
		public native set(Function func);
	}
	
	property Function OnSoundPost
	{
		public native set(Function func);
	}
	
	property Function OnSpokeConceptPost
	{
		public native set(Function func);
	}
	
	property Function OnNavAreaChangedPost
	{
		public native set(Function func);
	}
	
	property Function OnModelChangedPost
	{
		public native set(Function func);
	}
	
	property Function OnPickUpPost
	{
		public native set(Function func);
	}
	
	property Function OnShovedPost
	{
		public native set(Function func);
	}
	
	property Function OnBlindedPost
	{
		public native set(Function func);
	}
	
	property Function OnEnteredSpitPost
	{
		public native set(Function func);
	}
	
	property Function OnHitByVomitJarPost
	{
		public native set(Function func);
	}
	
	property Function OnCommandAttackPost
	{
		public native set(Function func);
	}
	
	property Function OnCommandAssaultPost
	{
		public native set(Function func);
	}
	
	property Function OnCommandApproachVPost
	{
		public native set(Function func);
	}
	
	property Function OnCommandApproachEPost
	{
		public native set(Function func);
	}
	
	property Function OnCommandRetreatPost
	{
		public native set(Function func);
	}
	
	property Function OnCommandPausePost
	{
		public native set(Function func);
	}
	
	property Function OnCommandResumePost
	{
		public native set(Function func);
	}
	
	property Function OnCommandStringPost
	{
		public native set(Function func);
	}
	
	property Function IsAbleToBlockMovementOfPost
	{
		public native set(Function func);
	}
};

methodmap BehaviorActionCustom < BehaviorAction
{
	public static native BehaviorActionCustom Create(const char[] name);
	// public native BehaviorActionCustom Delete();
	
	property Function OnStartPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}

	property Function OnUpdatePost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnEndPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnSuspendPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnResumePost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnInitialContainedActionPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnLeaveGroundPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnLandOnGroundPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnContactPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnMoveToSuccessPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnMoveToFailurePost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnStuckPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnUnStuckPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnPostureChangedPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnAnimationActivityCompletePost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnAnimationActivityInterruptedPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnAnimationEventPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnIgnitePost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnInjuredPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnKilledPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnOtherKilledPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnSightPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnLostSightPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnThreatChangedPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnSoundPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnSpokeConceptPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnNavAreaChangedPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnModelChangedPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnPickUpPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnShovedPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnBlindedPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnEnteredSpitPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnHitByVomitJarPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnCommandAttackPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnCommandAssaultPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnCommandApproachVPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	 
	property Function OnCommandApproachEPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnCommandRetreatPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnCommandPausePost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnCommandResumePost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function OnCommandStringPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
	
	property Function IsAbleToBlockMovementOfPost
	{
		public get()
		{
			return INVALID_FUNCTION;
		}
	}
}