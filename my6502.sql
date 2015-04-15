-- cat my6502.sql|mysql -u root
-- http://nesdev.com/6502.txt
-- ftp://ftp.apple.asimov.net/pub/apple_II/site_index.txt
-- ~/code/Apple/Virtual ][/APPLE2+.ROM

use my6502;
delimiter $$

-- update process status register N and Z
drop function if exists update_psr_nz;
create function update_psr_nz (p tinyint unsigned, a tinyint unsigned) returns tinyint unsigned deterministic
    return (p & 0x7D) | if(a >= 128, 0x80, 0) | if(a = 0, 0x02, 0);

-- update process status register N, Z and C
drop function if exists update_psr_nzc;
create function update_psr_nzc (p tinyint unsigned, a tinyint unsigned, c smallint) returns tinyint unsigned deterministic
    return (p & 0x7C) | if(a >= 128, 0x80, 0) | if(a = 0, 0x02, 0) | if(c, 0x01, 0);

-- update process status register N, Z, C and V
drop function if exists update_psr_nzcv;
create function update_psr_nzcv (p tinyint unsigned, a tinyint unsigned, c smallint, v smallint) returns tinyint unsigned deterministic
    return (p & 0x3C) | if(a >= 128, 0x80, 0) | if(a = 0, 0x02, 0) | if(c, 0x01, 0) | if(v, 0x40, 0);

-- new pc for a branch
drop function if exists maybe_branch;
create function maybe_branch (pc smallint unsigned, test tinyint unsigned, offset tinyint unsigned) returns smallint unsigned deterministic
    return pc + if(test, if(offset >= 128, cast(offset as signed) - 256, offset), 0);

-- get target byte and effective address for given opcode
drop procedure if exists get_operand;
create procedure get_operand (inst tinyint unsigned, out byte tinyint unsigned, out ea smallint unsigned, out pc_change smallint)
begin
    case ((inst >> 2) & 0x07)

        when 0 then  -- (absolute indirect,X)
            set pc_change = 3;

        when 1 then  -- zeropage
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram on op_ram.address = cpu.pc + 1
                join ram on ram.address = op_ram.value;
            set pc_change = 2;

        when 2 then  -- immediate
            select ram.value, ram.address into byte, ea from cpu
                join ram on ram.address = cpu.pc + 1;
            set pc_change = 2;

        when 3 then  -- absolute
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram_lo on op_ram_lo.address = cpu.pc + 1
                join ram as op_ram_hi on op_ram_hi.address = cpu.pc + 2
                join ram on ram.address = (op_ram_hi.value << 8) + op_ram_lo.value;
            set pc_change = 3;

        when 4 then  -- (absolute indirect),Y
            set pc_change = 3;

        when 5 then  -- zeropage,X
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram on op_ram.address = cpu.pc + 1
                join ram on ram.address = op_ram.value + cpu.x;
            set pc_change = 2;

        when 6 then  -- absolute,Y
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram_lo on op_ram_lo.address = cpu.pc + 1
                join ram as op_ram_hi on op_ram_hi.address = cpu.pc + 2
                join ram on ram.address = (op_ram_hi.value << 8) + op_ram_lo.value + cpu.y;
            set pc_change = 3;

        when 7 then  -- absolute,X
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram_lo on op_ram_lo.address = cpu.pc + 1
                join ram as op_ram_hi on op_ram_hi.address = cpu.pc + 2
                join ram on ram.address = (op_ram_hi.value << 8) + op_ram_lo.value + cpu.x;
            set pc_change = 3;
    end case;
end;


-- Interpreter --

drop procedure if exists run;
create procedure run ()
begin
    declare inst tinyint unsigned;
    declare byte tinyint unsigned;
    declare newbyte tinyint unsigned;
    declare ea smallint unsigned;
    declare pc_change smallint;

    main: loop
        -- next instruction
        select ram.value into inst from cpu join ram on ram.address = cpu.pc;
        case

            -- -- --  maths and logic  -- -- --

            when inst in (0x60, 0x61, 0x65, 0x69, 0x70, 0x71, 0x75, 0x79) then  -- ADC
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.a = if(cpu.p & 0x08,  -- decimal mode
                        @new := (@test := (@acc := cpu.a) + byte + (cpu.p & 0x01) + 
                            if(((@acc & 0x0F) + (byte & 0x0F) + (cpu.p & 0x01)) > 9, 6, 0)) +
                            if(@test > 0x99, 96, 0),
                        @new := (@acc := cpu.a) + byte + (cpu.p & 0x01)) & 0xFF,
                    cpu.p = if(cpu.p & 0x08,  -- decimal mode
                        update_psr_nzcv(cpu.p, @test, @new > 0x99, !((@acc ^ byte) & 0x80) && ((@acc ^ @test) & 0x80)),
                        update_psr_nzcv(cpu.p, @new, @new > 0xFF, !((@acc ^ byte) & 0x80) && ((@acc ^ @new) & 0x80))),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0x21, 0x25, 0x29, 0x2D, 0x31, 0x35, 0x39, 0x3D) then  -- AND
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.a = cpu.a & byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xC1, 0xC5, 0xC9, 0xCD, 0xD1, 0xD5, 0xD9, 0xDD) then  -- CMP
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.p = update_psr_nzc(cpu.p, cpu.a + 0x100 - byte & 0xFF, byte <= cpu.a),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xE0, 0xE4, 0xEC) then  -- CPX
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.p = update_psr_nzc(cpu.p, cpu.x + 0x100 - byte & 0xFF, byte <= cpu.x),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xC0, 0xC4, 0xCC) then  -- CPY
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.p = update_psr_nzc(cpu.p, cpu.y + 0x100 - byte & 0xFF, byte <= cpu.y),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xC6, 0xCE, 0xD6, 0xDE) then  -- DEC
                call get_operand(inst, byte, ea, pc_change);
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

            when inst in (0x40, 0x41, 0x45, 0x49, 0x50, 0x51, 0x55, 0x59) then  -- EOR
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.a = cpu.a ^ byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xE6, 0xEE, 0xF6, 0xFE) then  -- INC
                call get_operand(inst, byte, ea, pc_change);
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
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.a = cpu.a | byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xE1, 0xE5, 0xE9, 0xED, 0xF1, 0xF5, 0xF9, 0xFD) then  -- SBC
                call get_operand(inst, byte, ea, pc_change);
                -- DO ME

            when inst in (0x24, 0x2C) then  -- BIT
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.p = (cpu.p & 0x3D) | (byte & 0xC0) | if(cpu.a ^ byte, 0x00, 0x02),  -- N, V and Z
                    cpu.pc = cpu.pc + pc_change;


            -- -- --  bits go left and right  -- -- --

            when inst = 0x0A then  -- ASL accumulator
                update cpu set
                    cpu.a = @newbyte := ((@byte := cpu.a) << 1) & 0xFF,
                    cpu.p = update_psr_3(cpu.p, @newbyte, @byte & 0x80),
                    cpu.pc = cpu.pc + 1;

            when inst in (0x06, 0x0E, 0x16, 0x1E) then  -- ASL memory
                call get_operand(inst, byte, ea, pc_change);
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
                call get_operand(inst, byte, ea, pc_change);
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
                call get_operand(inst, byte, ea, pc_change);
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
                call get_operand(inst, byte, ea, pc_change);
                set newbyte = (byte >> 1) | if(byte & 0x01, 0x80, 0x00);
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_3(cpu.p, newbyte, byte & 0x01),
                    cpu.pc = cpu.pc + pc_change;


            -- -- --  transfers  -- -- --

            when inst in (0xA1, 0xA5, 0xA9, 0xAD, 0xB1, 0xB5, 0xB9, 0xBD) then  -- LDA
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.a = byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0x80, 0x81, 0x85, 0x90, 0x91, 0x95, 0x99) then  -- STA
                call get_operand(inst, byte, ea, pc_change);
                update cpu join ram on ram.address = ea set
                    ram.value = cpu.a,
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xA2, 0xA6, 0xAE, 0xB6, 0xBE) then  -- LDX
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.x = byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.x),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0xA0, 0xA4, 0xAC, 0xB4, 0xBC) then  -- LDY
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.y = byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.y),
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0x86, 0x8E, 0x96) then  -- STX
                call get_operand(inst, byte, ea, pc_change);
                update cpu join ram on ram.address = ea set
                    ram.value = cpu.x,
                    cpu.pc = cpu.pc + pc_change;

            when inst in (0x84, 0x8C, 0x94) then  -- STY
                call get_operand(inst, byte, ea, pc_change);
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

            when inst = 0x08 then  -- PLA
                update cpu join ram on ram.address = 0x100 + (cpu.s + 1 & 0xFF) set
                    cpu.a = ram.value,
                    cpu.s = cpu.s + 1 & 0xFF,
                    cpu.pc = cpu.pc + 1;

            when inst = 0x28 then  -- PLP
                update cpu join ram on ram.address = 0x100 + (cpu.s + 1 & 0xFF) set
                    cpu.p = ram.value,
                    cpu.s = cpu.s + 1 & 0xFF,
                    cpu.pc = cpu.pc + 1;


            -- -- --  branches  -- -- --

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
                select 42;

        end case;
        leave main;  -- DEBUG just one instruction, for testing
    end loop;
end;

$$
delimiter ;
