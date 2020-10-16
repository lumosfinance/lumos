const { expectRevert } = require('@openzeppelin/test-helpers');
const LumosToken = artifacts.require('LumosToken');

contract('LumosToken', ([alice, bob, carol]) => {
    beforeEach(async () => {
        this.lumos = await LumosToken.new({ from: alice });
    });

    it('should have correct name and symbol and decimal', async () => {
        const name = await this.lumos.name();
        const symbol = await this.lumos.symbol();
        const decimals = await this.lumos.decimals();
        assert.equal(name.valueOf(), 'LumosToken');
        assert.equal(symbol.valueOf(), 'LMS');
        assert.equal(decimals.valueOf(), '18');
    });

    it('should only allow owner to mint token', async () => {
        await this.lumos.mint(alice, '100', { from: alice });
        await this.lumos.mint(bob, '1000', { from: alice });
        await expectRevert(
            this.lumos.mint(carol, '1000', { from: bob }),
            'Ownable: caller is not the owner',
        );
        const totalSupply = await this.lumos.totalSupply();
        const aliceBal = await this.lumos.balanceOf(alice);
        const bobBal = await this.lumos.balanceOf(bob);
        const carolBal = await this.lumos.balanceOf(carol);
        assert.equal(totalSupply.valueOf(), '1100');
        assert.equal(aliceBal.valueOf(), '100');
        assert.equal(bobBal.valueOf(), '1000');
        assert.equal(carolBal.valueOf(), '0');
    });

    it('should supply token transfers properly', async () => {
        await this.lumos.mint(alice, '100', { from: alice });
        await this.lumos.mint(bob, '1000', { from: alice });
        await this.lumos.transfer(carol, '10', { from: alice });
        await this.lumos.transfer(carol, '100', { from: bob });
        const totalSupply = await this.lumos.totalSupply();
        const aliceBal = await this.lumos.balanceOf(alice);
        const bobBal = await this.lumos.balanceOf(bob);
        const carolBal = await this.lumos.balanceOf(carol);
        assert.equal(totalSupply.valueOf(), '1100');
        assert.equal(aliceBal.valueOf(), '90');
        assert.equal(bobBal.valueOf(), '900');
        assert.equal(carolBal.valueOf(), '110');
    });

    it('should fail if you try to do bad transfers', async () => {
        await this.lumos.mint(alice, '100', { from: alice });
        await expectRevert(
            this.lumos.transfer(carol, '110', { from: alice }),
            'ERC20: transfer amount exceeds balance',
        );
        await expectRevert(
            this.lumos.transfer(carol, '1', { from: bob }),
            'ERC20: transfer amount exceeds balance',
        );
    });
  });