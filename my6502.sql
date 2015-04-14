-- cat my6502.sql|mysql -u root
-- http://nesdev.com/6502.txt

-- to create the database and tables, uncomment FROM HERE...
-- drop database if exists my6502;
-- create database my6502
--     character set ascii;

-- use my6502;

-- create table ram (
--     address smallint unsigned not null primary key,
--     value tinyint unsigned not null default 0
-- ) engine = innodb;

-- create table cpu (
--     a tinyint unsigned not null default 0,
--     x tinyint unsigned not null default 0,
--     y tinyint unsigned not null default 0,
--     s tinyint unsigned not null default 0,
--     p tinyint unsigned not null default 0,
--     pc smallint unsigned not null default 0
-- ) engine = innodb;

-- create table screen (
--     screen text character set ascii not null
-- ) engine = innodb;

-- delimiter $$

-- create trigger ram_after_update after update on ram
-- for each row begin
--     declare ix integer;
--     if NEW.address >= 0x400 and NEW.address < 0x800 then  -- text screen
--         set ix = NEW.address - 0x400;
--         set ix = ix + 1;  -- DEBUG skip over newline
--         update screen set screen = concat(left(screen, ix), char(NEW.value), substring(screen, ix+2));
--     end if;
-- end;

-- $$
-- delimiter ;
-- ...TO HERE
-- then call create_machine();


use my6502;
delimiter $$

drop procedure if exists create_machine;
create procedure create_machine ()
begin
    declare a int;

    delete from ram;
    set a = 0;
    while a <= 0xFFFF do
        insert into ram (address) values
            (a+0x00),(a+0x01),(a+0x02),(a+0x03),(a+0x04),(a+0x05),(a+0x06),(a+0x07),(a+0x08),(a+0x09),(a+0x0A),(a+0x0B),(a+0x0C),(a+0x0D),(a+0x0E),(a+0x0F),
            (a+0x10),(a+0x11),(a+0x12),(a+0x13),(a+0x14),(a+0x15),(a+0x16),(a+0x17),(a+0x18),(a+0x19),(a+0x1A),(a+0x1B),(a+0x1C),(a+0x1D),(a+0x1E),(a+0x1F),
            (a+0x20),(a+0x21),(a+0x22),(a+0x23),(a+0x24),(a+0x25),(a+0x26),(a+0x27),(a+0x28),(a+0x29),(a+0x2A),(a+0x2B),(a+0x2C),(a+0x2D),(a+0x2E),(a+0x2F),
            (a+0x30),(a+0x31),(a+0x32),(a+0x33),(a+0x34),(a+0x35),(a+0x36),(a+0x37),(a+0x38),(a+0x39),(a+0x3A),(a+0x3B),(a+0x3C),(a+0x3D),(a+0x3E),(a+0x3F);
        set a = a + 0x40;
    end while;

    delete from cpu;
    insert into cpu (a) values (0);

    delete from screen;
    insert into screen (screen) values (repeat(concat("\n", repeat(" ", 40)), 24));

    call hard_reset();
end;

drop procedure if exists hard_reset;
create procedure hard_reset ()
begin
    update ram set value = 0;
    update cpu set a = 0, x = 0, y = 0, s = 0, p = 0, pc = 0x0300;  -- p should be 0x20
end;


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
create function update_psr_nzcv (p tinyint unsigned, a tinyint unsigned, c smallint) returns tinyint unsigned deterministic
    return (p & 0x3C) | if(a >= 128, 0x80, 0) | if(a >= 64, 0x40, 0) | if(a = 0, 0x02, 0) | if(c, 0x01, 0);


-- new pc for a branch
drop function if exists maybe_branch;
create function maybe_branch (pc smallint unsigned, test tinyint unsigned, offset tinyint unsigned) returns smallint unsigned deterministic
    return if(test, 2 + if(offset >= 128, cast(offset as signed) - 256, offset), 2);

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
                join ram on ram.address = op_ram_lo.value + op_ram_hi.value * 256;
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
                join ram on ram.address = op_ram_lo.value + op_ram_hi.value * 256 + cpu.y;
            set pc_change = 3;

        when 7 then  -- absolute,X
            select ram.value, ram.address into byte, ea from cpu
                join ram as op_ram_lo on op_ram_lo.address = cpu.pc + 1
                join ram as op_ram_hi on op_ram_hi.address = cpu.pc + 2
                join ram on ram.address = op_ram_lo.value + op_ram_hi.value * 256 + cpu.x;
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
    declare t integer;
    declare addr smallint unsigned;

    main: loop
        -- next instruction
        select ram.value into inst from cpu join ram on ram.address = cpu.pc;
        case

            -- -- --  maths and logic  -- -- --

            when inst in (0x60, 0x61, 0x65, 0x69, 0x70, 0x71, 0x75, 0x79) then  -- ADC
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.a = (@a := (cpu.a + byte + (cpu.p & 0x01))) & 0xFF,
                    cpu.p = update_psr_nzcv(cpu.p, cpu.a, @a > 255),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst in (0x21, 0x25, 0x29, 0x2D, 0x31, 0x35, 0x39, 0x3D) then  -- AND
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.a = cpu.a & byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst in (0xC1, 0xC5, 0xC9, 0xCD, 0xD1, 0xD5, 0xD9, 0xDD) then  -- CMP
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.p = update_psr_nzc(cpu.p, cpu.a + 256 - byte & 0xFF, byte < cpu.a),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            -- CPX
            -- CPY

            when inst in (0xC6, 0xCE, 0xD6, 0xDE) then  -- DEC
                call get_operand(inst, byte, ea, pc_change);
                set newbyte = byte + 256 - 1 & 0xFF;
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_nz(cpu.p, newbyte),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst = 0xCA then  -- DEX
                update cpu set
                    cpu.x = @newbyte := cpu.x + 256 - 1 & 0xFF,
                    cpu.p = update_psr_nz(cpu.p, @newbyte),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst = 0x88 then  -- DEY
                update cpu set
                    cpu.y = @newbyte := cpu.y + 256 - 1 & 0xFF,
                    cpu.p = update_psr_nz(cpu.p, @newbyte),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst in (0x40, 0x41, 0x45, 0x49, 0x50, 0x51, 0x55, 0x59) then  -- EOR
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.a = cpu.a ^ byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst in (0xE6, 0xEE, 0xF6, 0xFE) then  -- INC
                call get_operand(inst, byte, ea, pc_change);
                set newbyte = byte + 1 & 0xFF;
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_nz(cpu.p, newbyte),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst = 0xE8 then  -- INX
                update cpu set
                    cpu.x = @newbyte := cpu.x + 1 & 0xFF,
                    cpu.p = update_psr_nz(cpu.p, @newbyte),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst = 0xC8 then  -- INY
                update cpu set
                    cpu.y = @newbyte := cpu.y + 1 & 0xFF,
                    cpu.p = update_psr_nz(cpu.p, @newbyte),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst in (0x01, 0x05, 0x09, 0x0D, 0x11, 0x15, 0x19, 0x1D) then  -- ORA
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.a = cpu.a | byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            -- SBC


            -- -- --  bits go left and right  -- -- --

            when inst = 0x0A then  -- ASL accumulator
                update cpu set
                    cpu.a = @newbyte := (@byte := cpu.a) << 1 & 0xFF,
                    cpu.p = update_psr_3(cpu.p, @newbyte, @byte & 0x80),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst in (0x06, 0x0E, 0x16, 0x1E) then  -- ASL memory
                call get_operand(inst, byte, ea, pc_change);
                set newbyte = byte << 1 & 0xFF;  -- necessary to do this outside of the update since the order of column updates is undefined
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_3(cpu.p, newbyte, byte & 0x80),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst = 0x4A then  -- LSR accumulator
                update cpu set
                    cpu.a = @newbyte := (@byte := cpu.a) >> 1,
                    cpu.p = update_psr_3(cpu.p, @newbyte, @byte & 0x01),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst in (0x46, 0x4E, 0x56, 0x5E) then  -- LSR memory
                call get_operand(inst, byte, ea, pc_change);
                set newbyte = byte >> 1;
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_3(cpu.p, newbyte, byte & 0x01),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst = 0x2A then  -- ROL accumulator
                update cpu set
                    cpu.a = @newbyte := (@byte := cpu.a) << 1 | if(cpu.a & 0x80, 0x01, 0x00) & 0xFF,
                    cpu.p = update_psr_3(cpu.p, @newbyte, @byte & 0x80),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst in (0x26, 0x2E, 0x36, 0x3E) then  -- ROL memory
                call get_operand(inst, byte, ea, pc_change);
                set newbyte = byte << 1 | if(byte & 0x80, 0x01, 0x00) & 0xFF;
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_3(cpu.p, newbyte, byte & 0x80),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst = 0x6A then  -- ROR accumulator
                update cpu set
                    cpu.a = @newbyte := (@byte := cpu.a) >> 1 | if(cpu.a & 0x01, 0x80, 0x00),
                    cpu.p = update_psr_3(cpu.p, @newbyte, @byte & 0x01),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst in (0x66, 0x6E, 0x76, 0x7E) then  -- ROR memory
                call get_operand(inst, byte, ea, pc_change);
                set newbyte = byte >> 1 | if(byte & 0x01, 0x80, 0x00);
                update cpu join ram on ram.address = ea set
                    ram.value = newbyte,
                    cpu.p = update_psr_3(cpu.p, newbyte, byte & 0x01),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;


            -- -- --  transfers  -- -- --

            when inst in (0xA1, 0xA5, 0xA9, 0xAD, 0xB1, 0xB5, 0xB9, 0xBD) then  -- LDA
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.a = byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst in (0x80, 0x81, 0x85, 0x90, 0x91, 0x95, 0x99) then  -- STA
                call get_operand(inst, byte, ea, pc_change);
                update cpu join ram on ram.address = ea set
                    ram.value = cpu.a,
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst in (0xA2, 0xA6, 0xAE, 0xB6, 0xBE) then  -- LDX
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.x = byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.x),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst in (0xA0, 0xA4, 0xAC, 0xB4, 0xBC) then  -- LDY
                call get_operand(inst, byte, ea, pc_change);
                update cpu set
                    cpu.y = byte,
                    cpu.p = update_psr_nz(cpu.p, cpu.y),
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst in (0x86, 0x8E, 0x96) then  -- STX
                call get_operand(inst, byte, ea, pc_change);
                update cpu join ram on ram.address = ea set
                    ram.value = cpu.x,
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst in (0x84, 0x8C, 0x94) then  -- STY
                call get_operand(inst, byte, ea, pc_change);
                update cpu join ram on ram.address = ea set
                    ram.value = cpu.y,
                    cpu.pc = cpu.pc + pc_change & 0xFFFF;

            when inst = 0xAA then  -- TAX
                update cpu set
                    cpu.x = cpu.a,
                    cpu.p = update_psr_nz(cpu.p, cpu.x),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst = 0xA8 then  -- TAY
                update cpu set
                    cpu.y = cpu.a,
                    cpu.p = update_psr_nz(cpu.p, cpu.y),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst = 0x8A then  -- TXA
                update cpu set
                    cpu.a = cpu.x,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst = 0x98 then  -- TYA
                update cpu set
                    cpu.a = cpu.y,
                    cpu.p = update_psr_nz(cpu.p, cpu.a),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst = 0xBA then  -- TSX
                update cpu set
                    cpu.x = cpu.s,
                    cpu.p = update_psr_nz(cpu.p, cpu.x),
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            when inst = 0x9A then  -- TXS
                update cpu set
                    cpu.s = cpu.x,
                    cpu.pc = cpu.pc + 1 & 0xFFFF;

            -- PHA
            -- PHP
            -- PLA
            -- PLP


            -- -- --  branches  -- -- --

            when inst = 0xF0 then  -- BEQ
                update cpu join ram on ram.address = cpu.pc + 1 set
                    cpu.pc = cpu.pc + maybe_branch(cpu.p & 0x02 != 0, ram.value) & 0xFFFF;

            when inst = 0xD0 then  -- BNE
                update cpu join ram on ram.address = cpu.pc + 1 set
                    cpu.pc = cpu.pc + maybe_branch(cpu.p & 0x02 = 0, ram.value) & 0xFFFF;

            -- BCC
            -- BCS
            -- BMI
            -- BPL
            -- BVC
            -- BVS


            -- -- --  status register fiddling  -- -- --

            when inst = 0x18 then  -- CLC
                update cpu set
                    cpu.p = cpu.p & 0xFE;

            -- CLD
            -- CLI
            -- CLV
            -- SEC
            -- SED
            -- SEI


            -- -- --  jumps  -- -- --

            when inst = 0x4C then  -- JMP <absolute>
                select ram_lo.value + ram_hi.value * 256 into addr from cpu
                    join ram as ram_lo on ram_lo.address = cpu.pc + 1
                    join ram as ram_hi on ram_hi.address = cpu.pc + 2;
                update cpu set
                    cpu.pc = addr & 0xFFFF;

            when inst = 0x6C then  -- JMP (<indirect>)
                select ind_ram_lo.value + ind_ram_hi.value * 256 into addr from cpu
                    join ram as ram_lo on ram_lo.address = cpu.pc + 1
                    join ram as ram_hi on ram_hi.address = cpu.pc + 2
                    join ram as ind_ram_lo on ind_ram_lo.address = ram_lo.value + ram_hi.value * 256
                    join ram as ind_ram_hi on ind_ram_hi.address = ram_lo.value + ram_hi.value * 256 + 1;
                update cpu set
                    cpu.pc = addr & 0xFFFF;

            -- BRK
            -- JSR
            -- RTI
            -- RTS


            -- -- --  misc  -- -- --
            -- BIT
            -- NOP


        end case;
        leave main;  -- DEBUG just one instruction, for testing
    end loop;
end;

$$
