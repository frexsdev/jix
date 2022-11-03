// zig fmt: off
pub const JixError = error{
    StackOverflow, 
    StackUnderflow, 
    IllegalInst, 
    IllegalInstAccess, 
    DivByZero, 
    IllegalOperand, 
    MissingOperand, 
    IntegerOverflow, 
    UndefinedLabel,
    UnknownNative,
    UnknownDirective,
    RedefinedLabel,
    ExceededMaxIncludeLevel,
};
// zig fmt: on
