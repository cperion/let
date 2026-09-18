-- The diagnostic vocabulary: one sum, three constructors.
--
-- `Reject` is the program's fault, `Missing` is a mechanism the compiler lacks, `Bug` is a broken
-- invariant. They are never conflated in a message string, because they are never a string: a
-- node returns one of these and *its parent* decides the policy (DESIGN §7, §13).
--
-- `MissingWhy` is the gap inventory. The count is the number of alternatives, every gap site
-- names its constructor, and a new gap cannot be added silently -- it is a visible alternative
-- that every dispatcher must handle. That is what replaces a hand-maintained GAPS.md.
return function(context)
    context:Define [[
module Report {
    RejectWhy  = UninitializedPlace | PartiallyInitialized | OwnershipDiverges | NeedsMove
               | IndexOutOfRange | UnstatedResult
               | ConflictingBorrow | BorrowedEscapes | BorrowOfTemporary
               | Oversaturated | Undersaturated | NotExecutable
               | DuplicateBinding | UnknownName | UseBeforeInitializer
               | ReadOnlyDestination | UnknownType | MismatchedType
               | MissingModule | ImportPath | ImportCycle
               | InvalidConversion | InvalidCaseLabel
               | Syntax(string detail)
    MissingWhy = ModuleState
    BugWhy     = UnresolvedWordValue | MissingProgramBuilder | NoLowering(string form)
               | UncarriedProducer | AnalysisExhausted | UnaddressableDestination

    Diagnostic = Reject(RejectWhy why, Source.Span span)
               | Missing(MissingWhy why, Source.Span span)
               | Bug(BugWhy why, Source.Span span)
}
    ]]

    -- The builders and predicates a machine uses. They live here so that no site spells a
    -- diagnostic itself, and so that "is this a Reject?" is asked in one place.
    local R = context.Report
    function R.reject(why, span) return R.Reject(why, span) end
    function R.missing(why, span) return R.Missing(why, span) end
    function R.bug(why, span) return R.Bug(why, span) end
    function R.Diagnostic:is_reject() return R.Reject:isclassof(self) end
    function R.Diagnostic:is_missing() return R.Missing:isclassof(self) end
    function R.Diagnostic:is_bug() return R.Bug:isclassof(self) end
    -- The gap inventory, as a value rather than a document: one entry per Missing reason.
    R.missing_reasons = { 'ModuleState' }
end

