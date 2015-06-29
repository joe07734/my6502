-- cat my6502.sql|mysql -u root

-- http://nesdev.com/6502.txt (note: inaccurate!)
-- ftp://ftp.apple.asimov.net/pub/apple_II/site_index.txt
-- ~/code/Apple/Virtual ][/APPLE2+.ROM

use my6502;
delimiter $$


-- -- -- -- -- -- -- -- -- -- -- -- --
--
--    update process status register
--
-- -- -- -- -- -- -- -- -- -- -- -- --

-- update process status register N and Z
drop function if exists update_psr_nz;
create function update_psr_nz (psr tinyint unsigned, a tinyint unsigned) returns tinyint unsigned deterministic
    return (psr & 0x7D) | if(a >= 128, 0x80, 0) | if(a = 0, 0x02, 0);

-- update process status register N, Z and C
drop function if exists update_psr_nzc;
create function update_psr_nzc (psr tinyint unsigned, a tinyint unsigned, c smallint) returns tinyint unsigned deterministic
    return (psr & 0x7C) | if(a >= 128, 0x80, 0) | if(a = 0, 0x02, 0) | if(c, 0x01, 0);

-- update process status register N, Z, C and V
drop function if exists update_psr_nzcv;
create function update_psr_nzcv (psr tinyint unsigned, a tinyint unsigned, c smallint, v smallint) returns tinyint unsigned deterministic
    return (psr & 0x3C) | if(a >= 128, 0x80, 0) | if(a = 0, 0x02, 0) | if(c, 0x01, 0) | if(v, 0x40, 0);


-- -- -- -- -- -- -- -- -- -- -- -- --
--
--    address for a branch
--
-- -- -- -- -- -- -- -- -- -- -- -- --

-- new pc for a branch
drop function if exists maybe_branch;
create function maybe_branch (pc smallint unsigned, test tinyint unsigned, offset tinyint unsigned) returns smallint unsigned deterministic
    return pc + 2 + if(test, if(offset >= 128, cast(offset as signed) - 256, offset), 0);


-- -- -- -- -- -- -- -- -- -- -- -- --
--
--    get addressing mode
--
-- -- -- -- -- -- -- -- -- -- -- -- --

-- get addressing mode for instruction encoding style a: ADC, AND, CMP, EOR, LDA, ORA, SBC, STA
--  0 1001  imm      09               
--  0 0101  zp       05
--  1 0101  zp,x     15
--  0 1101  abs      0D
--  1 1101  abs,x    1D
--  1 1001  abs,y    19
--  0 0001  (ind,x)  01
--  1 0001  (ind),y  11
drop function if exists addressing_mode_a;
create function addressing_mode_a (inst tinyint unsigned) returns tinyint unsigned deterministic
    case (inst & 0x1D)
        when 0x09 then  -- immediate
            return 0;
        when 0x05 then  -- zero page
            return 1;
        when 0x15 then  -- zero page,X
            return 2;
        when 0x0D then  -- absolute
            return 3;
        when 0x1D then  -- absolute,X
            return 4;
        when 0x19 then  -- absolute,Y
            return 5;
        when 0x01 then  -- (indirect,X)
            return 6;
        when 0x11 then  -- (indirect),Y
            return 7;
    end case;

-- get addressing mode for instruction encoding style b: LDX, STX
--  0 0010  imm    02
--  0 0110  zp     06
--  0 1110  abs    0E
--  1 1110  abs,y  1E
--  1 0110  zp,y   16
drop function if exists addressing_mode_b;
create function addressing_mode_b (inst tinyint unsigned) returns tinyint unsigned deterministic
    case (inst & 0x1E)
        when 0x02 then  -- immediate
            return 0;
        when 0x06 then  -- zero page
            return 1;
        when 0x0E then  -- absolute
            return 3;
        when 0x1E then  -- absolute,Y
            return 5;
        when 0x16 then  -- zero page,Y
            return 8;
    end case;

-- get addressing mode for instruction encoding style c: BIT, CPX, CPY, LDY, STY
--  0 0000  imm    00
--  0 0100  zp     04
--  1 0100  zp,x   14
--  0 1100  abs    0C
--  1 1100  abs,x  1C
drop function if exists addressing_mode_c;
create function addressing_mode_c (inst tinyint unsigned) returns tinyint unsigned deterministic
    case (inst & 0x1C)
        when 0x00 then  -- immediate
            return 0;
        when 0x04 then  -- zero page
            return 1;
        when 0x14 then  -- zero page,X
            return 2;
        when 0x0C then  -- absolute
            return 3;
        when 0x1C then  -- absolute,X
            return 4;
    end case;

-- get addressing mode for instruction encoding style d: ASL, DEC, INC, LSR, ROL, ROR
--  0 0110  zp     06
--  1 0110  zp,x   16
--  0 1110  abs    0E
--  1 1110  abs,x  1E
drop function if exists addressing_mode_d;
create function addressing_mode_d (inst tinyint unsigned) returns tinyint unsigned deterministic
    case (inst & 0x1E)
        when 0x06 then  -- zero page
            return 1;
        when 0x16 then  -- zero page,X
            return 2;
        when 0x0E then  -- absolute
            return 3;
        when 0x1E then  -- absolute,X
            return 4;
    end case;


-- -- -- -- -- -- -- -- -- -- -- -- --
--
--    get operand
--
-- -- -- -- -- -- -- -- -- -- -- -- --

-- get operand and effective address for given addressing mode:
--  0  immediate
--  1  zero page
--  2  zero page,X
--  3  absolute
--  4  absolute,X
--  5  absolute,Y
--  6  (indirect,X)
--  7  (indirect),Y
--  8  zero page,Y
drop procedure if exists get_operand;
create procedure get_operand (addressing_mode tinyint unsigned, out byte tinyint unsigned, out ea smallint unsigned, out pc_change smallint)
begin
    case addressing_mode

        when 0 then  -- immediate
            select ram.value, ram.address into byte, ea from cpu
                join ram on ram.address = cpu.pc + 1;
            set pc_change = 2;

        when 1 then  -- zero page
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram on op_ram.address = cpu.pc + 1
                join ram on ram.address = op_ram.value;
            set pc_change = 2;

        when 2 then  -- zero page,X
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram on op_ram.address = cpu.pc + 1
                join ram on ram.address = op_ram.value + cpu.x;
            set pc_change = 2;

        when 3 then  -- absolute
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram_lo on op_ram_lo.address = cpu.pc + 1
                join ram as op_ram_hi on op_ram_hi.address = cpu.pc + 2
                join ram on ram.address = (op_ram_hi.value << 8) + op_ram_lo.value;
            set pc_change = 3;

        when 4 then  -- absolute,X
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram_lo on op_ram_lo.address = cpu.pc + 1
                join ram as op_ram_hi on op_ram_hi.address = cpu.pc + 2
                join ram on ram.address = (op_ram_hi.value << 8) + op_ram_lo.value + cpu.x;
            set pc_change = 3;

        when 5 then  -- absolute,Y
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram_lo on op_ram_lo.address = cpu.pc + 1
                join ram as op_ram_hi on op_ram_hi.address = cpu.pc + 2
                join ram on ram.address = (op_ram_hi.value << 8) + op_ram_lo.value + cpu.y;
            set pc_change = 3;

        when 6 then  -- (indirect,X)
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram on op_ram.address = cpu.pc + 1
                join ram as ind_ram_lo on ind_ram_lo.address = op_ram.value + cpu.x & 0xFF
                join ram as ind_ram_hi on ind_ram_hi.address = op_ram.value + cpu.x + 1 & 0xFF
                join ram on ram.address = (ind_ram_hi.value << 8) + ind_ram_lo.value;
            set pc_change = 2;

        when 7 then  -- (indirect),Y
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram on op_ram.address = cpu.pc + 1
                join ram as ind_ram_lo on ind_ram_lo.address = op_ram.value
                join ram as ind_ram_hi on ind_ram_hi.address = op_ram.value + 1
                join ram on ram.address = (ind_ram_hi.value << 8) + ind_ram_lo.value + cpu.y;
            set pc_change = 2;

        when 8 then  -- zero page,Y
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram on op_ram.address = cpu.pc + 1
                join ram on ram.address = op_ram.value + cpu.y;
            set pc_change = 2;

    end case;
end;


-- -- -- -- -- -- -- -- -- -- -- -- --
--
--    interpreter
--
-- -- -- -- -- -- -- -- -- -- -- -- --

drop procedure if exists run;
create procedure run (initial_pc smallint unsigned, num_steps smallint unsigned)
begin
    declare inst tinyint unsigned;
    declare byte tinyint unsigned;
    declare newbyte tinyint unsigned;
    declare ea smallint unsigned;
    declare pc_change smallint;

    update cpu set cpu.pc = initial_pc;

    main: loop
        -- next instruction
        select ram.value into inst from cpu join ram on ram.address = cpu.pc;
        case

            -- -- --  maths and logics  -- -- --

            when inst in (0x61, 0x65, 0x69, 0x6D, 0x71, 0x75, 0x79, 0x7D) then  -- ADC
                call get_operand(addressing_mode_a(inst), byte, ea, pc_change);
                update cpu set
                    -- @new: new value before clipping
                    -- @test: new decimal value before wrapping
                    cpu.a = if(cpu.p & 0x08,  -- decimal mode?
                            @new := (@test := (@acc := cpu.a) + byte + (cpu.p & 0x01) + 
                                if(((@acc & 0x0F) + (byte & 0x0F) + (cpu.p & 0x01)) > 9, 6, 0)) +
                                if(@test > 0x99, 0x60, 0),
                            @new := (@acc := cpu.a) + byte + (cpu.p & 0x01)
                        ) & 0xFF,
                    cpu.p = if(cpu.p & 0x08,  -- decimal mode?
                        update_psr_nzcv(cpu.p, @test, @new > 0x99, !((@acc ^ byte) & 0x80) && ((@acc ^ @test) & 0x80)),
                        update_psr_nzcv(cpu.p, @new,  @new > 0xFF, !((@acc ^ byte) & 0x80) && ((@acc ^ @new) & 0x80))),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0x21, 0x25, 0x29, 0x2D, 0x31, 0x35, 0x39, 0x3D) then  -- AND
                call get_operand(addressing_mode_a(inst), byte, ea, pc_change);
                update cpu set
                    cpu.a = cpu.a & byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xC1, 0xC5, 0xC9, 0xCD, 0xD1, 0xD5, 0xD9, 0xDD) then  -- CMP
                call get_operand(addressing_mode_a(inst), byte, ea, pc_change);
                update cpu set
                    cpu.p = update_psr_nzc(cpu.p, cpu.a + 0x100 - byte & 0xFF, byte <= cpu.a),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xE0, 0xE4, 0xEC) then  -- CPX
                call get_operand(addressing_mode_c(inst), byte, ea, pc_change);
                update cpu set
                    cpu.p = update_psr_nzc(cpu.p, cpu.x + 0x100 - byte & 0xFF, byte <= cpu.x),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xC0, 0xC4, 0xCC) then  -- CPY
                call get_operand(addressing_mode_c(inst), byte, ea, pc_change);
                update cpu set
                    cpu.p = update_psr_nzc(cpu.p, cpu.y + 0x100 - byte & 0xFF, byte <= cpu.y),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xC6, 0xCE, 0xD6, 0xDE) then  -- DEC
                call get_operand(addressing_mode_d(inst), byte, ea, pc_change);
                set newbyte = byte + 0x100 - 1 & 0xFF;
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_nz(cpu.p, newbyte),
                    cpu.pc = cpu.pc + pc_change;

            when inst = 0xCA then  -- DEX
                update cpu set
                    cpu.x = @newbyte := cpu.x + 0x100 - 1 & 0xFF,
                    cpu.p = update_psr_nz(cpu.p, @newbyte),
                    cpu.pc = cpu.pc + 1;

            when inst = 0x88 then  -- DEY
                update cpu set
                    cpu.y = @newbyte := cpu.y + 0x100 - 1 & 0xFF,
                    cpu.p = update_psr_nz(cpu.p, @newbyte),
                    cpu.pc = cpu.pc + 1;

            when inst in (0x41, 0x45, 0x49, 0x4D, 0x51, 0x55, 0x59, 0x5D) then  -- EOR
                call get_operand(addressing_mode_a(inst), byte, ea, pc_change);
                update cpu set
                    cpu.a = cpu.a ^ byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xE6, 0xEE, 0xF6, 0xFE) then  -- INC
                call get_operand(addressing_mode_d(inst), byte, ea, pc_change);
                set newbyte = byte + 1 & 0xFF;
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_nz(cpu.p, newbyte),
                    cpu.pc = cpu.pc + pc_change;

            when inst = 0xE8 then  -- INX
                update cpu set
                    cpu.x = @newbyte := cpu.x + 1 & 0xFF,
                    cpu.p = update_psr_nz(cpu.p, @newbyte),
                    cpu.pc = cpu.pc + 1;

            when inst = 0xC8 then  -- INY
                update cpu set
                    cpu.y = @newbyte := cpu.y + 1 & 0xFF,
                    cpu.p = update_psr_nz(cpu.p, @newbyte),
                    cpu.pc = cpu.pc + 1;

            when inst in (0x01, 0x05, 0x09, 0x0D, 0x11, 0x15, 0x19, 0x1D) then  -- ORA
                call get_operand(addressing_mode_a(inst), byte, ea, pc_change);
                update cpu set
                    cpu.a = cpu.a | byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xE1, 0xE5, 0xE9, 0xED, 0xF1, 0xF5, 0xF9, 0xFD) then  -- SBC
                call get_operand(addressing_mode_a(inst), byte, ea, pc_change);
                update cpu set
                    -- @new: new value before clipping
                    -- @test: new decimal value before wrapping
                    cpu.a = if(cpu.p & 0x08,  -- decimal mode?
                            @new := (@test := (@acc := cpu.a) - byte - if(cpu.p & 0x01, 0, 1) -
                                if( ((@acc & 0x0F) - if(cpu.p & 0x01, 0, 1)) < (byte & 0x0F), 6, 0)) -
                                if(@test > 0x99, 0x60, 0),
                            @new := (@acc := cpu.a) - byte - if(cpu.p & 0x01, 0, 1)
                        ) & 0xFF,
                    cpu.p = if(cpu.p & 0x08,  -- decimal mode?
                        update_psr_nzcv(cpu.p, @test, @new < 0x100, ((@acc ^ @test) & 0x80) && ((@acc ^ byte) & 0x80)),
                        update_psr_nzcv(cpu.p, @new,  @new < 0x100, ((@acc ^ @new) & 0x80) && ((@acc ^ byte) & 0x80))),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0x24, 0x2C) then  -- BIT
                call get_operand(addressing_mode_c(inst), byte, ea, pc_change);
                update cpu set
                    cpu.p = (cpu.p & 0x3D) | (byte & 0xC0) | if(cpu.a ^ byte, 0x00, 0x02),  -- N, V and Z
                    cpu.pc = cpu.pc + pc_change;


            -- -- --  bits go left and right and around  -- -- --

            when inst = 0x0A then  -- ASL accumulator
                update cpu set
                    cpu.a = @newbyte := ((@byte := cpu.a) << 1) & 0xFF,
                    cpu.p = update_psr_3(cpu.p, @newbyte, @byte & 0x80),
                    cpu.pc = cpu.pc + 1;

            when inst in (0x06, 0x0E, 0x16, 0x1E) then  -- ASL memory
                call get_operand(addressing_mode_d(inst), byte, ea, pc_change);
                set newbyte = (byte << 1) & 0xFF;  -- necessary to do this outside of the update since the order of column updates is undefined
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_3(cpu.p, newbyte, byte & 0x80),
                    cpu.pc = cpu.pc + pc_change;

            when inst = 0x4A then  -- LSR accumulator
                update cpu set
                    cpu.a = @newbyte := (@byte := cpu.a) >> 1,
                    cpu.p = update_psr_3(cpu.p, @newbyte, @byte & 0x01),
                    cpu.pc = cpu.pc + 1;

            when inst in (0x46, 0x4E, 0x56, 0x5E) then  -- LSR memory
                call get_operand(addressing_mode_d(inst), byte, ea, pc_change);
                set newbyte = byte >> 1;
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_3(cpu.p, newbyte, byte & 0x01),
                    cpu.pc = cpu.pc + pc_change;

            when inst = 0x2A then  -- ROL accumulator
                update cpu set
                    cpu.a = @newbyte := ((@byte := cpu.a) << 1) | if(cpu.a & 0x80, 0x01, 0x00) & 0xFF,
                    cpu.p = update_psr_3(cpu.p, @newbyte, @byte & 0x80),
                    cpu.pc = cpu.pc + 1;

            when inst in (0x26, 0x2E, 0x36, 0x3E) then  -- ROL memory
                call get_operand(addressing_mode_d(inst), byte, ea, pc_change);
                set newbyte = (byte << 1) | if(byte & 0x80, 0x01, 0x00) & 0xFF;
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_3(cpu.p, newbyte, byte & 0x80),
                    cpu.pc = cpu.pc + pc_change;

            when inst = 0x6A then  -- ROR accumulator
                update cpu set
                    cpu.a = @newbyte := ((@byte := cpu.a) >> 1) | if(cpu.a & 0x01, 0x80, 0x00),
                    cpu.p = update_psr_3(cpu.p, @newbyte, @byte & 0x01),
                    cpu.pc = cpu.pc + 1;

            when inst in (0x66, 0x6E, 0x76, 0x7E) then  -- ROR memory
                call get_operand(addressing_mode_d(inst), byte, ea, pc_change);
                set newbyte = (byte >> 1) | if(byte & 0x01, 0x80, 0x00);
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_3(cpu.p, newbyte, byte & 0x01),
                    cpu.pc = cpu.pc + pc_change;


            -- -- --  transfers happen  -- -- --

            when inst in (0xA1, 0xA5, 0xA9, 0xAD, 0xB1, 0xB5, 0xB9, 0xBD) then  -- LDA
                call get_operand(addressing_mode_a(inst), byte, ea, pc_change);
                update cpu set
                    cpu.a = byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xA2, 0xA6, 0xAE, 0xB6, 0xBE) then  -- LDX
                call get_operand(addressing_mode_b(inst), byte, ea, pc_change);
                update cpu set
                    cpu.x = byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.x),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xA0, 0xA4, 0xAC, 0xB4, 0xBC) then  -- LDY
                call get_operand(addressing_mode_c(inst), byte, ea, pc_change);
                update cpu set
                    cpu.y = byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.y),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0x81, 0x85, 0x8D, 0x91, 0x95, 0x99, 0x9D) then  -- STA
                call get_operand(addressing_mode_a(inst), byte, ea, pc_change);
                update cpu join ram on ram.address = ea set
                    ram.value = cpu.a,
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0x86, 0x8E, 0x96) then  -- STX
                call get_operand(addressing_mode_b(inst), byte, ea, pc_change);
                update cpu join ram on ram.address = ea set
                    ram.value = cpu.x,
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0x84, 0x8C, 0x94) then  -- STY
                call get_operand(addressing_mode_c(inst), byte, ea, pc_change);
                update cpu join ram on ram.address = ea set
                    ram.value = cpu.y,
                    cpu.pc = cpu.pc + pc_change;

            when inst = 0xAA then  -- TAX
                update cpu set
                    cpu.x = cpu.a,
                    cpu.p = update_psr_nz(cpu.p, cpu.x),
                    cpu.pc = cpu.pc + 1;

            when inst = 0xA8 then  -- TAY
                update cpu set
                    cpu.y = cpu.a,
                    cpu.p = update_psr_nz(cpu.p, cpu.y),
                    cpu.pc = cpu.pc + 1;

            when inst = 0x8A then  -- TXA
                update cpu set
                    cpu.a = cpu.x,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + 1;

            when inst = 0x98 then  -- TYA
                update cpu set
                    cpu.a = cpu.y,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + 1;

            when inst = 0xBA then  -- TSX
                update cpu set
                    cpu.x = cpu.s,
                    cpu.p = update_psr_nz(cpu.p, cpu.x),
                    cpu.pc = cpu.pc + 1;

            when inst = 0x9A then  -- TXS
                update cpu set
                    cpu.s = cpu.x,
                    cpu.pc = cpu.pc + 1;

            when inst = 0x48 then  -- PHA
                update cpu join ram on ram.address = 0x100 + cpu.s set
                    ram.value = cpu.a,
                    cpu.s = cpu.s + 0x100 - 1 & 0xFF,
                    cpu.pc = cpu.pc + 1;

            when inst = 0x08 then  -- PHP
                update cpu join ram on ram.address = 0x100 + cpu.s set
                    ram.value = cpu.p,
                    cpu.s = cpu.s + 0x100 - 1 & 0xFF,
                    cpu.pc = cpu.pc + 1;

            when inst = 0x68 then  -- PLA
                update cpu join ram on ram.address = 0x100 + (cpu.s + 1 & 0xFF) set
                    cpu.a = ram.value,
                    cpu.s = cpu.s + 1 & 0xFF,
                    cpu.pc = cpu.pc + 1;

            when inst = 0x28 then  -- PLP
                update cpu join ram on ram.address = 0x100 + (cpu.s + 1 & 0xFF) set
                    cpu.p = ram.value,
                    cpu.s = cpu.s + 1 & 0xFF,
                    cpu.pc = cpu.pc + 1;


            -- -- --  branching  -- -- --

            when inst = 0xF0 then  -- BEQ
                update cpu join ram on ram.address = cpu.pc + 1 set
                    cpu.pc = maybe_branch(cpu.pc, cpu.p & 0x02 != 0, ram.value);

            when inst = 0xD0 then  -- BNE
                update cpu join ram on ram.address = cpu.pc + 1 set
                    cpu.pc = maybe_branch(cpu.pc, cpu.p & 0x02 = 0, ram.value);

            when inst = 0x90 then  -- BCC
                update cpu join ram on ram.address = cpu.pc + 1 set
                    cpu.pc = maybe_branch(cpu.pc, cpu.p & 0x01 = 0, ram.value);

            when inst = 0xB0 then  -- BCS
                update cpu join ram on ram.address = cpu.pc + 1 set
                    cpu.pc = maybe_branch(cpu.pc, cpu.p & 0x01 != 0, ram.value);

            when inst = 0x30 then  -- BMI
                update cpu join ram on ram.address = cpu.pc + 1 set
                    cpu.pc = maybe_branch(cpu.pc, cpu.p & 0x80 != 0, ram.value);

            when inst = 0x10 then  -- BPL
                update cpu join ram on ram.address = cpu.pc + 1 set
                    cpu.pc = maybe_branch(cpu.pc, cpu.p & 0x80 = 0, ram.value);

            when inst = 0x50 then  -- BVC
                update cpu join ram on ram.address = cpu.pc + 1 set
                    cpu.pc = maybe_branch(cpu.pc, cpu.p & 0x40 = 0, ram.value);

            when inst = 0x70 then  -- BVS
                update cpu join ram on ram.address = cpu.pc + 1 set
                    cpu.pc = maybe_branch(cpu.pc, cpu.p & 0x40 != 0, ram.value);


            -- -- --  status register fiddling  -- -- --

            when inst = 0x18 then  -- CLC
                update cpu set
                    cpu.p = cpu.p & 0xFE;

            when inst = 0xD8 then  -- CLD
                update cpu set
                    cpu.p = cpu.p & 0xF7;

            when inst = 0x58 then  -- CLI
                update cpu set
                    cpu.p = cpu.p & 0xFB;

            when inst = 0xB8 then  -- CLV
                update cpu set
                    cpu.p = cpu.p & 0xBF;

            when inst = 0x38 then  -- SEC
                update cpu set
                    cpu.p = cpu.p | 0x01;

            when inst = 0xF8 then  -- SED
                update cpu set
                    cpu.p = cpu.p | 0x04;

            when inst = 0x78 then  -- SEI
                update cpu set
                    cpu.p = cpu.p | 0x02;


            -- -- --  jumps  -- -- --

            when inst = 0x4C then  -- JMP <absolute>
                update cpu
                    join ram as ram_lo on ram_lo.address = cpu.pc + 1
                    join ram as ram_hi on ram_hi.address = cpu.pc + 2
                    set cpu.pc = (ram_hi.value << 8) + ram_lo.value;

            when inst = 0x6C then  -- JMP (<indirect>)
                update cpu
                    join ram as ram_lo on ram_lo.address = cpu.pc + 1
                    join ram as ram_hi on ram_hi.address = cpu.pc + 2
                    join ram as ind_ram_lo on ind_ram_lo.address = (ram_hi.value << 8) + ram_lo.value
                    join ram as ind_ram_hi on ind_ram_hi.address = (ram_hi.value << 8) + ram_lo.value + 1
                    set cpu.pc = (ind_ram_hi.value << 8) + ind_ram_lo.value;

            when inst = 0x20 then  -- JSR
                update cpu
                    join ram AS stack_hi on stack_hi.address = 0x100 + cpu.s
                    join ram AS stack_lo on stack_lo.address = 0x100 + (cpu.s + 0x100 - 1 & 0xFF)
                    set
                    stack_hi.value = ((cpu.pc - 1) >> 8) & 0xFF,
                    stack_lo.value = (cpu.pc - 1) & 0xFF,
                    cpu.s = cpu.s + 0x100 - 2 & 0xFF;
                update cpu
                    join ram as ram_lo on ram_lo.address = cpu.pc + 1
                    join ram as ram_hi on ram_hi.address = cpu.pc + 2
                    set cpu.pc = (ram_hi.value << 8) + ram_lo.value;

            when inst = 0x60 then  -- RTS
                update cpu
                    join ram AS stack_lo on stack_lo.address = 0x100 + (cpu.s + 1 & 0xFF)
                    join ram AS stack_hi on stack_hi.address = 0x100 + (cpu.s + 2 & 0xFF)
                    set
                    cpu.pc = (stack_hi.value << 8) + stack_lo.value + 1,
                    cpu.s = cpu.s + 2 & 0xFF;

            when inst = 0x00 then  -- BRK
                update cpu
                    join ram AS stack_hi on stack_hi.address = 0x100 + cpu.s
                    join ram AS stack_lo on stack_lo.address = 0x100 + (cpu.s + 0x100 - 1 & 0xFF)
                    join ram AS stack_p on stack_p.address = 0x100 + (cpu.s + 0x100 - 2 & 0xFF)
                    set
                    stack_hi.value = ((cpu.pc + 1) >> 8) & 0xFF,
                    stack_lo.value = (cpu.pc + 1) & 0xFF,
                    stack_p.value = cpu.p | 0x10,  -- include break flag
                    cpu.s = cpu.s + 0x100 - 2 & 0xFF;
                update cpu
                    join ram as ram_lo on ram_lo.address = 0xFFFE
                    join ram as ram_hi on ram_hi.address = 0xFFFF
                    set
                    cpu.p = cpu.p | 0x14,  -- set interrupt disable flag (and break flag for real)
                    cpu.pc = (ram_hi.value << 8) + ram_lo.value;

            when inst = 0x4D then  -- RTI
                update cpu
                    join ram AS stack_p on stack_p.address = 0x100 + (cpu.s + 1 & 0xFF)
                    join ram AS stack_lo on stack_lo.address = 0x100 + (cpu.s + 2 & 0xFF)
                    join ram AS stack_hi on stack_hi.address = 0x100 + (cpu.s + 3 & 0xFF)
                    set
                    cpu.p = stack_p.value,
                    cpu.pc = (stack_hi.value << 8) + stack_lo.value,
                    cpu.s = cpu.s + 3 & 0xFF;


            -- -- --  misc  -- -- --

            when inst = 0xEA then  -- NOP
                update cpu set cpu.pc = cpu.pc + 1;

            when inst = 0xFF then  -- DEBUG HALT
                set num_steps = 1;


            -- -- --  for future expansion  -- -- --

            else
                update cpu set cpu.pc = cpu.pc + 1;

        end case;

        update stats set instructions = instructions + 1;

        -- set num_steps to 0 to run forever
        if num_steps > 0 then
            set num_steps = num_steps - 1;
            if num_steps = 0 then
                leave main;
            end if;
        end if;

    end loop;
end;

$$
delimiter ;
