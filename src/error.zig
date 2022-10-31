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
    UnknownLabel
};
// zig fmt: on
