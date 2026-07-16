import { Controller, Get, Post, Delete, Body, Param, Query, Headers, Ip } from '@nestjs/common';
import { PhoneLookupService } from './phone-lookup.service';
import { SyncContactsDto } from './dto/sync-contacts.dto';

@Controller('phone-lookup')
export class PhoneLookupController {
  constructor(private readonly phoneLookupService: PhoneLookupService) {}

  @Post('sync')
  async syncContacts(@Body() dto: SyncContactsDto) {
    return await this.phoneLookupService.syncContacts(dto);
  }

  @Post('tag')
  async addTag(
    @Body('phoneNumberId') phoneNumberId: string,
    @Body('labelName') labelName: string,
    @Body('userId') userId?: string,
  ) {
    return await this.phoneLookupService.createTag(phoneNumberId, labelName, userId);
  }

  @Post('vote')
  async voteTag(
    @Body('tagId') tagId: string,
    @Body('userId') userId: string,
    @Body('voteType') voteType: 'UPVOTE' | 'DOWNVOTE',
  ) {
    return await this.phoneLookupService.voteTag(tagId, userId, voteType);
  }

  @Post('send-otp')
  async sendOtp(@Body('phoneNumber') phoneNumber: string, @Body('isResend') isResend?: boolean) {
    return await this.phoneLookupService.sendOtp(phoneNumber, isResend);
  }

  @Post('verify-otp')
  async verifyOtp(
    @Body('phoneNumber') phoneNumber: string,
    @Body('code') code: string,
  ) {
    return await this.phoneLookupService.verifyOtp(phoneNumber, code);
  }

  @Get('analytics')
  async getAnalytics() {
    return await this.phoneLookupService.getAnalytics();
  }

  @Get(':number')
  async lookup(
    @Param('number') number: string,
    @Query('skipIncrement') skipIncrement?: string,
    @Headers('x-device-id') deviceId?: string,
    @Headers('x-has-contact-access') hasContactAccess?: string,
    @Ip() ip?: string,
  ) {
    return await this.phoneLookupService.lookupPhoneNumber(
      number,
      skipIncrement === 'true',
      deviceId || ip || 'unknown-device',
      hasContactAccess === 'true',
    );
  }

  @Get('searchers/:number')
  async getSearchers(
    @Param('number') number: string,
    @Query('limit') limit?: string,
  ) {
    // 1. Cari dulu ID dari nomor telepon ini
    const phoneRecord = await this.phoneLookupService['prisma'].phoneNumber.findUnique({
      where: { phoneNumber: number.trim().replace(/\s+/g, '') },
    });
    
    if (!phoneRecord) {
      return { success: true, data: [] }; // Jika nomor belum pernah dicari sama sekali
    }

    // 2. Ambil riwayat pencari berdasarkan ID tersebut
    const maxLimit = limit ? parseInt(limit, 10) : 100;
    const searchers = await this.phoneLookupService.getPhoneSearchers(phoneRecord.id, maxLimit);
    
    // 3. Format response untuk frontend
    // Pastikan timeAgo di-generate secara real-time berdasarkan lastSearchedAt
    const now = new Date();
    const formattedSearchers = searchers.map(history => {
      const diffMs = now.getTime() - history.lastSearchedAt.getTime();
      const diffMins = Math.floor(diffMs / 60000);
      const diffHours = Math.floor(diffMins / 60);
      const diffDays = Math.floor(diffHours / 24);
      
      let timeStr = 'Baru saja';
      if (diffDays > 0) timeStr = `${diffDays} hari yang lalu`;
      else if (diffHours > 0) timeStr = `${diffHours} jam yang lalu`;
      else if (diffMins > 0) timeStr = `${diffMins} menit yang lalu`;
      
      return {
        ...history,
        timeAgo: `Memeriksa nomor Anda | ${timeStr}`,
      };
    });

    return {
      success: true,
      data: formattedSearchers,
    };
  }

  @Delete('reset/:number')
  async resetNumberData(@Param('number') number: string) {
    return await this.phoneLookupService.resetPhoneNumberData(number);
  }
}
